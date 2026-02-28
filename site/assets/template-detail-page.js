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

  const versionSelect = document.getElementById("versionSelect");
  if (versionSelect) {
    versionSelect.addEventListener("change", (event) => {
      const targetUrl = event.target.value;
      if (!targetUrl) return;
      window.location.href = targetUrl;
    });
  }

  const copyBtn = document.getElementById("copyBtn");
  const templateUrlCode = document.getElementById("templateUrlCode");
  if (copyBtn && templateUrlCode) {
    copyBtn.addEventListener("click", () => {
      const shareUrl = toAbsoluteUrl(templateUrlCode.textContent || "");
      if (!shareUrl) return;

      const originalText = copyBtn.textContent;
      copyText(shareUrl)
        .then(() => {
          copyBtn.textContent = "Copied!";
          copyBtn.classList.add("copied");
        })
        .catch(() => {
          copyBtn.textContent = "Copy failed";
        })
        .finally(() => {
          setTimeout(() => {
            copyBtn.textContent = originalText;
            copyBtn.classList.remove("copied");
          }, 1800);
        });
    });
  }
})();
