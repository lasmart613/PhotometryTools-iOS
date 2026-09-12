(function () {
  var status = document.getElementById("status");
  if (!status) return;

  var item = document.createElement("li");
  item.textContent = "Placeholder JS loaded — waiting for totalservicepro-web asset sync";
  status.appendChild(item);
})();
