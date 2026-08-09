window.addEventListener("DOMContentLoaded", () => {
  const csrf = document
    .querySelector("meta[name='csrf-token']")
    ?.getAttribute("content");

  const liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
    params: { _csrf_token: csrf },
  });

  liveSocket.connect();
  window.liveSocket = liveSocket;
});
