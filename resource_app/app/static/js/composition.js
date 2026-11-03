document.addEventListener("DOMContentLoaded", () => {
  const tbody = document.getElementById("composition-body");
  const addBtn = document.getElementById("add-composition-row");
  const form = document.getElementById("ressource-form");
  const totalEl = document.getElementById("composition-total");
  if (!tbody || !totalEl) return;

  function recalc() {
    let total = 0;
    tbody.querySelectorAll("input[name='comp_pct']").forEach((input) => {
      total += parseFloat(input.value) || 0;
    });
    totalEl.textContent = total.toFixed(2);
    const ok = Math.abs(total - 100) < 0.01;
    totalEl.classList.toggle("text-success", ok);
    totalEl.classList.toggle("text-danger", !ok);
    return ok;
  }

  addBtn?.addEventListener("click", () => {
    const first = tbody.querySelector("tr");
    if (!first) return;
    const row = first.cloneNode(true);
    row.querySelectorAll("input, select").forEach((el) => {
      if (el.tagName === "SELECT") {
        el.selectedIndex = 0;
      } else {
        el.value = "";
      }
    });
    tbody.appendChild(row);
    recalc();
  });

  tbody.addEventListener("click", (event) => {
    const button = event.target.closest(".remove-composition-row");
    if (!button) return;
    if (tbody.querySelectorAll("tr").length > 1) {
      button.closest("tr").remove();
      recalc();
    }
  });

  tbody.addEventListener("input", recalc);
  tbody.addEventListener("change", recalc);

  form?.addEventListener("submit", (event) => {
    if (!recalc()) {
      event.preventDefault();
      alert("La composition doit totaliser 100 %.");
    }
  });

  recalc();
});
