// The clipper's options: the key Point gave it, kept in the extension's own storage.
const field = document.getElementById("key");
const saved = document.getElementById("saved");

chrome.storage.local.get("key").then(({ key }) => {
  field.value = key || "";
});

field.addEventListener("input", async () => {
  await chrome.storage.local.set({ key: field.value.trim() });
  saved.textContent = "Saved.";
});
