const walletList = document.querySelector("#wallet-list");
const toast = document.querySelector("#toast");
const wallets = window.deadwoodSupport?.wallets ?? [];

function showToast(message) {
  toast.textContent = message;
  toast.classList.add("is-visible");
  window.clearTimeout(showToast.timeout);
  showToast.timeout = window.setTimeout(() => {
    toast.classList.remove("is-visible");
  }, 2200);
}

async function copyAddress(address) {
  try {
    await navigator.clipboard.writeText(address);
    showToast("Address copied");
  } catch {
    showToast("Could not copy — select the address manually");
  }
}

function walletCard(wallet) {
  const hasAddress = Boolean(wallet.address?.trim());
  const article = document.createElement("article");
  article.className = "wallet-card";

  const top = document.createElement("div");
  top.className = "wallet-top";

  const coin = document.createElement("span");
  coin.className = "coin";
  coin.textContent = wallet.symbol;

  const state = document.createElement("span");
  state.className = "wallet-state";
  state.textContent = hasAddress ? "Available" : "Coming soon";

  top.append(coin, state);

  const name = document.createElement("h3");
  name.textContent = wallet.name;

  const network = document.createElement("p");
  network.className = "network";
  network.textContent = wallet.network;

  const row = document.createElement("div");
  row.className = "address-row";

  const address = document.createElement("div");
  address.className = "address";
  address.title = hasAddress ? wallet.address : "Address not published yet";
  address.textContent = hasAddress ? wallet.address : "Address will be published here";

  const copy = document.createElement("button");
  copy.className = "copy-button";
  copy.type = "button";
  copy.disabled = !hasAddress;
  copy.textContent = hasAddress ? "Copy" : "Pending";
  copy.setAttribute("aria-label", hasAddress
    ? `Copy ${wallet.name} address`
    : `${wallet.name} address is not available yet`
  );
  copy.addEventListener("click", () => copyAddress(wallet.address));

  row.append(address, copy);
  article.append(top, name, network, row);
  return article;
}

if (wallets.length === 0) {
  walletList.textContent = "Donation options are being prepared.";
} else {
  wallets.forEach((wallet) => walletList.append(walletCard(wallet)));
}
