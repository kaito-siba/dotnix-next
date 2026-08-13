function getRepoAndPRCode() {
  const url = window.location.href;
  const match = url.match(/github\.com\/([^\/]+)\/([^\/]+)\/pull\/(\d+)/);
  if (match) {
    const repositoryName = match[2];
    const prCode = match[3];
    return `${repositoryName}_${prCode}`;
  }
  return null;
}

try {
  const result = getRepoAndPRCode();
  if (!result) {
    throw new Error("Not a PR page");
  }
  // writeText is async; without .catch a rejection escapes the try/catch.
  window.navigator.clipboard.writeText(result).catch(error => console.error(error));
} catch (error) {
  console.error(error.message);
}
