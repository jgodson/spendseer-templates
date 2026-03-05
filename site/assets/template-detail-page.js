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

  document.addEventListener("click", (event) => {
    const btn = event.target.closest(".code-copy-btn");
    if (!btn) return;
    const code = btn.closest(".code-block")?.querySelector("pre code");
    if (!code) return;
    const originalText = btn.textContent;
    copyText(code.textContent || "")
      .then(() => {
        btn.textContent = "Copied!";
        btn.classList.add("copied");
      })
      .catch(() => {
        btn.textContent = "Copy failed";
      })
      .finally(() => {
        setTimeout(() => {
          btn.textContent = originalText;
          btn.classList.remove("copied");
        }, 1800);
      });
  });

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
