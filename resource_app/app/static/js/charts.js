function renderDashboardCharts(data) {
  const doughnut = document.getElementById("chartStatuts");
  if (doughnut) {
    new Chart(doughnut, {
      type: "doughnut",
      data: {
        labels: data.statuts_labels,
        datasets: [{ data: data.statuts_values }],
      },
      options: { plugins: { legend: { position: "bottom" } } },
    });
  }

  const bar = document.getElementById("chartMateriaux");
  if (bar) {
    new Chart(bar, {
      type: "bar",
      data: {
        labels: data.materiaux_labels,
        datasets: [{ label: "Ressources", data: data.materiaux_values }],
      },
      options: { scales: { y: { beginAtZero: true, ticks: { precision: 0 } } } },
    });
  }

  const line = document.getElementById("chartTransactions");
  if (line) {
    new Chart(line, {
      type: "line",
      data: {
        labels: data.tx_labels,
        datasets: [{ label: "Transactions", data: data.tx_values, fill: false }],
      },
      options: { scales: { y: { beginAtZero: true, ticks: { precision: 0 } } } },
    });
  }
}

function renderScenarioChart(labels, costs, values) {
  const canvas = document.getElementById("chartScenarios");
  if (!canvas) return;
  new Chart(canvas, {
    type: "bar",
    data: {
      labels,
      datasets: [
        { label: "Coût estimé", data: costs },
        { label: "Valeur estimée", data: values },
      ],
    },
    options: { scales: { y: { beginAtZero: true } } },
  });
}
