#!/usr/bin/env python3
import csv
import sys


POS_TYPES = {
    "NO_POS": 0,
    "NOUN": 1,
    "ABBREVIATION": 2,
    "SUGGESTION_ONLY": 3,
    "PROPER_NOUN": 4,
    "PERSONAL_NAME": 5,
    "FAMILY_NAME": 6,
    "FIRST_NAME": 7,
    "ORGANIZATION_NAME": 8,
    "PLACE_NAME": 9,
    "SA_IRREGULAR_CONJUGATION_NOUN": 10,
    "ADJECTIVE_VERBAL_NOUN": 11,
    "NUMBER": 12,
    "ALPHABET": 13,
    "SYMBOL": 14,
    "EMOTICON": 15,
    "ADVERB": 16,
    "PRENOUN_ADJECTIVAL": 17,
    "CONJUNCTION": 18,
    "INTERJECTION": 19,
    "PREFIX": 20,
    "COUNTER_SUFFIX": 21,
    "GENERIC_SUFFIX": 22,
    "PERSON_NAME_SUFFIX": 23,
    "PLACE_NAME_SUFFIX": 24,
    "WA_GROUP1_VERB": 25,
    "KA_GROUP1_VERB": 26,
    "SA_GROUP1_VERB": 27,
    "TA_GROUP1_VERB": 28,
    "NA_GROUP1_VERB": 29,
    "MA_GROUP1_VERB": 30,
    "RA_GROUP1_VERB": 31,
    "GA_GROUP1_VERB": 32,
    "BA_GROUP1_VERB": 33,
    "HA_GROUP1_VERB": 34,
    "GROUP2_VERB": 35,
    "KURU_GROUP3_VERB": 36,
    "SURU_GROUP3_VERB": 37,
    "ZURU_GROUP3_VERB": 38,
    "RU_GROUP3_VERB": 39,
    "ADJECTIVE": 40,
    "SENTENCE_ENDING_PARTICLE": 41,
    "PUNCTUATION": 42,
    "FREE_STANDING_WORD": 43,
    "SUPPRESSION_WORD": 44,
    "品詞なし": 0,
    "名詞": 1,
    "短縮よみ": 2,
    "サジェストのみ": 3,
    "固有名詞": 4,
    "人名": 5,
    "姓": 6,
    "名": 7,
    "組織": 8,
    "地名": 9,
    "名詞サ変": 10,
    "名詞形動": 11,
    "数": 12,
    "アルファベット": 13,
    "記号": 14,
    "顔文字": 15,
    "副詞": 16,
    "連体詞": 17,
    "接続詞": 18,
    "感動詞": 19,
    "接頭語": 20,
    "助数詞": 21,
    "接尾一般": 22,
    "接尾人名": 23,
    "接尾地名": 24,
    "動詞ワ行五段": 25,
    "動詞カ行五段": 26,
    "動詞サ行五段": 27,
    "動詞タ行五段": 28,
    "動詞ナ行五段": 29,
    "動詞マ行五段": 30,
    "動詞ラ行五段": 31,
    "動詞ガ行五段": 32,
    "動詞バ行五段": 33,
    "動詞ハ行四段": 34,
    "動詞一段": 35,
    "動詞カ変": 36,
    "動詞サ変": 37,
    "動詞ザ変": 38,
    "動詞ラ変": 39,
    "形容詞": 40,
    "終助詞": 41,
    "句読点": 42,
    "独立語": 43,
    "抑制単語": 44,
}


def varint(value):
    out = bytearray()
    while value > 0x7F:
        out.append((value & 0x7F) | 0x80)
        value >>= 7
    out.append(value)
    return bytes(out)


def tag(field_number, wire_type):
    return varint((field_number << 3) | wire_type)


def field_varint(field_number, value):
    return tag(field_number, 0) + varint(value)


def field_bytes(field_number, value):
    if isinstance(value, str):
        value = value.encode("utf-8")
    return tag(field_number, 2) + varint(len(value)) + value


def parse_pos(value, line_number):
    value = value or "名詞"
    pos_name, separator, locale = value.partition(":")
    if pos_name not in POS_TYPES:
        raise ValueError(f"line {line_number}: unknown POS: {pos_name}")
    return POS_TYPES[pos_name], locale if separator else ""


def entry_message(row, line_number):
    if len(row) not in (3, 4):
        raise ValueError(f"line {line_number}: expected 3 or 4 tab-separated columns")

    key, value, pos_name = row[:3]
    comment = row[3] if len(row) == 4 else ""
    if not key:
        raise ValueError(f"line {line_number}: key is empty")
    if not value:
        raise ValueError(f"line {line_number}: value is empty")

    pos, locale = parse_pos(pos_name, line_number)
    message = bytearray()
    message += field_bytes(1, key)
    message += field_bytes(2, value)
    if comment:
        message += field_bytes(4, comment)
    message += field_varint(5, pos)
    if locale:
        message += field_bytes(12, locale)
    return bytes(message)


def load_entries(path):
    entries = []
    with open(path, encoding="utf-8", newline="") as file:
        reader = csv.reader(file, delimiter="\t")
        for line_number, row in enumerate(reader, start=1):
            if not row or not any(cell.strip() for cell in row):
                continue
            if row[0].startswith("#"):
                continue
            if line_number == 1 and [cell.lower() for cell in row[:4]] == [
                "key",
                "value",
                "pos",
                "comment",
            ]:
                continue
            entries.append(entry_message(row, line_number))
    return entries


def dictionary_message(entries):
    message = bytearray()
    message += field_varint(1, 1)
    message += field_varint(2, 1)
    message += field_bytes(3, "Nix")
    for entry in entries:
        message += field_bytes(4, entry)
    return bytes(message)


def storage_message(entries):
    dictionary = dictionary_message(entries)
    message = bytearray()
    message += field_varint(1, 0)
    message += field_bytes(2, dictionary)
    message += field_varint(10, 1)
    return bytes(message)


def main():
    if len(sys.argv) != 3:
        print("usage: mozc-user-dictionary-to-db.py INPUT.tsv OUTPUT.db", file=sys.stderr)
        return 2

    entries = load_entries(sys.argv[1])
    with open(sys.argv[2], "wb") as file:
        file.write(storage_message(entries))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
