// aw-secretary (kaito-siba/aw-secretary の serve) の commitment の API に聞く口。Inbox の dialog を開くたびに 1 つ作り、両方の面で使う
// 聞くのは 1 度に 1 つで、答えが返るまで次を送らない。答えの順が入れ替わらず、続けて押した時に server で後の物が先に適用されない
// 答えを待ったまま dialog を閉じると、次に開いた dialog はその答えを待たない

// 答えの view で置き換える。書けなかった時は前の view を残す。collect の最中の 503 は running: true が付くので、前の view に重ねて key を止める
export const merge = (view, got) => got.answer?.items ? got.answer : got.running && view ? { ...view, running: true } : view;

export class Secretary {
  constructor(url) {
    this.url = url;
    // busy は答えを待っている call があるか。queued は送る順を待っている書き込みで、writing は答えを待っている書き込み
    this.busy = false; this.queued = null; this.writing = false;
    // 送る順を待っている読み。key ごとに最後の 1 つだけを送る
    this.reads = new Map();
    // この dialog で書いた操作の取り消しの token と、取り消した時に出す label。新しい物が後ろ
    this.undos = [];
  }

  // 答えを待っている書き込みがあるか
  waiting() { return Boolean(this.queued) || this.writing; }

  // 書き込みは、前の書き込みの答えを待っている間は受けない。受けなかった時は false。読みの答えを待っている間は、その後に送る
  // done は ({ answer, error, running, status }, cx) を受ける。error の時の running は、collect の最中の 503 の印。status は落ちていて答えが無い時は null
  // undo は取り消す時に出す { label, id, title }。答えに token があれば積む
  write(cx, path, body, done, undo) {
    if (!this.url || this.waiting()) return false;
    this.queued = { path, body, done, undo };
    this.next(cx);
    return true;
  }

  read(cx, key, path, done) {
    if (!this.url) return;
    this.reads.delete(key);
    this.reads.set(key, { path, done });
    this.next(cx);
  }

  // 送る順を待っている読みを捨てる
  drop(key) { this.reads.delete(key); }

  // 答えを待っていなければ、次を送る。書き込みを読みより先に送る
  next(cx) {
    if (this.busy) return;
    let job = this.queued;
    if (job) { this.queued = null; this.writing = true; }
    else {
      const first = this.reads.entries().next().value;
      if (!first) return;
      this.reads.delete(first[0]);
      job = first[1];
    }
    this.busy = true;
    cx.spawn(async cx => {
      const got = { answer: null, error: null, running: false, status: null };
      try {
        const r = await (job.body
          ? fetch(`${this.url}${job.path}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(job.body) })
          : fetch(`${this.url}${job.path}`));
        const j = await r.json().catch(() => null);
        got.status = r.status;
        if (r.ok && j) got.answer = j;
        else { got.error = j?.error ?? `aw-secretary answered ${r.status}`; got.running = j?.running ?? false; }
      } catch (e) { got.error = String(e?.message ?? e); }
      finally {
        this.busy = false;
        if (job.body) this.writing = false;
        if (job.undo && got.answer?.undo) this.undos.push({ ...job.undo, token: got.answer.undo });
        job.done(got, cx);
        this.next(cx);
        cx.notify();
      }
    });
  }
}
