(() => {
  function toAbsoluteUrl(url) {
    if (!url) return "";

    try {
      return new URL(url, window.location.origin).toString();
    } catch (_error) {
      return url;
    }
  }

  function copyText(text) {
    if (!text) return Promise.reject(new Error("Missing text"));
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text);
    }

    return new Promise((resolve, reject) => {
      const textarea = document.createElement("textarea");
      textarea.value = text;
      textarea.setAttribute("readonly", "");
      textarea.style.position = "fixed";
      textarea.style.opacity = "0";
      document.body.appendChild(textarea);
      textarea.select();

      try {
        if (document.execCommand("copy")) {
          resolve();
        } else {
          reject(new Error("Copy failed"));
        }
      } catch (error) {
        reject(error);
      } finally {
        document.body.removeChild(textarea);
      }
    });
  }

  document.querySelectorAll(".card-copy-btn").forEach((button) => {
    button.addEventListener("click", () => {
      const shareUrl = toAbsoluteUrl(button.dataset.shareUrl || "");
      if (!shareUrl) return;

      const originalText = button.textContent;
      copyText(shareUrl)
        .then(() => {
          button.textContent = "Copied!";
          button.classList.add("copied");
        })
        .catch(() => {
          button.textContent = "Copy failed";
        })
        .finally(() => {
          setTimeout(() => {
            button.textContent = originalText;
            button.classList.remove("copied");
          }, 1800);
        });
    });
  });
})();
