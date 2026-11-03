const $ = (selector) => document.querySelector(selector);
const types = {
  stream: "Transmissão",
  audio: "Áudio gravado",
  public_page: "Página pública",
  podcast_feed: "Podcast (RSS)",
};
let csrf = "",
  items = [],
  editId = null,
  toastTimer;
async function api(path, options = {}) {
  const response = await fetch("/api/" + path, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      "X-CSRF-Token": csrf,
      ...options.headers,
    },
  });
  if (response.status === 204) return null;
  const data = await response.json();
  if (!response.ok) {
    if (response.status === 401 && path !== "admin/login") showLogin();
    throw new Error(data.error || "Não foi possível concluir.");
  }
  return data;
}
function message(text, error = false) {
  const box = $("#feedback");
  box.textContent = text;
  box.classList.toggle("error", error);
  box.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (box.hidden = true), 6500);
}
function showLogin() {
  csrf = "";
  $("#dashboard").hidden = true;
  $("#login").hidden = false;
  $("#password").focus();
}
function resetEditor() {
  editId = null;
  $("#content-form").reset();
  $("#editor-title").textContent = "Adicionar conteúdo";
  $("#cancel").hidden = true;
  updateType();
}
function updateType() {
  const podcastPage =
    /\/public\/[a-zA-Z0-9_-]+\/podcasts?\/[a-zA-Z0-9_-]+(?:\/feed)?\/?$/.test(
      $("#url").value.split(/[?#]/)[0],
    );
  const link = $("#type").value === "public_page" && !podcastPage;
  const primary = $("#content-form").elements.primary;
  primary.disabled = link;
  if (link) primary.checked = false;
  $("#url-help").textContent =
    $("#type").value === "podcast_feed" ||
    (podcastPage && $("#type").value === "public_page")
      ? "Use o RSS ou a página pública do podcast no AzuraCast. Como principal, os episódios serão reproduzidos em sequência e em loop."
      : link
        ? "Esta página será publicada como link, sem reprodução de áudio."
        : "Use o endereço direto do áudio ou da transmissão.";
}
const icons = {
  edit: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m16 3 5 5-12 12-6 1 1-6Z M14 5l5 5"/></svg>',
  delete:
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 6h18 M9 6V3h6v3 M5 6l1 15h12l1-15 M10 10v7 M14 10v7"/></svg>',
};
async function loadContents() {
  items = await api("admin/contents");
  const body = $("#contents");
  body.replaceChildren();
  if (!items.length) {
    const row = body.insertRow();
    const cell = row.insertCell();
    cell.colSpan = 4;
    cell.className = "empty";
    cell.textContent =
      "Nenhum conteúdo cadastrado. Adicione o primeiro link abaixo.";
  }
  for (const item of items) {
    const row = body.insertRow();
    const title = row.insertCell();
    title.textContent = item.title;
    const subtitle = document.createElement("small");
    subtitle.textContent =
      (item.primary ? "Reprodução principal · " : "") + item.url;
    title.append(subtitle);
    row.insertCell().textContent = types[item.type];
    const badge = document.createElement("span");
    badge.className = "badge" + (item.published ? " published" : "");
    badge.textContent = item.published ? "Ativo" : "Rascunho";
    row.insertCell().append(badge);
    const actions = document.createElement("div");
    actions.className = "row-actions";
    for (const action of ["edit", "delete"]) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "icon-button " + action;
      button.setAttribute(
        "aria-label",
        `${action === "edit" ? "Editar" : "Excluir"} ${item.title}`,
      );
      button.innerHTML = icons[action];
      button.onclick = () => (action === "edit" ? edit(item) : remove(item));
      actions.append(button);
    }
    row.insertCell().append(actions);
  }
}
function edit(item) {
  editId = item.id;
  const form = $("#content-form");
  for (const key of ["title", "type", "url", "description"])
    form.elements[key].value = item[key];
  for (const key of ["published", "primary", "rightsConfirmed"])
    form.elements[key].checked = item[key];
  $("#editor-title").textContent = "Editar conteúdo";
  $("#cancel").hidden = false;
  updateType();
  $("#title").focus();
}
async function remove(item) {
  const dialog = $("#delete-dialog");
  dialog.returnValue = "";
  dialog.showModal();
  dialog.addEventListener(
    "close",
    async () => {
      if (dialog.returnValue !== "delete") return;
      try {
        await api("admin/contents/" + item.id, { method: "DELETE" });
        if (editId === item.id) resetEditor();
        await loadContents();
        message("Conteúdo excluído.");
      } catch (e) {
        message(e.message, true);
      }
    },
    { once: true },
  );
}
async function loadStorageStatus() {
  try {
    const storage = await api("admin/storage");
    $("#storage-status").textContent =
      `${storage.mode === "remote" ? "Banco remoto persistente" : "Banco local de desenvolvimento"} · ${storage.contents} conteúdo(s) cadastrado(s)`;
    $("#storage-identity").textContent = storage.databaseId;
    const warning = $("#storage-warning");
    try {
      const previous = localStorage.getItem("luzia:lastDatabaseId");
      if (previous && previous !== storage.databaseId) {
        warning.textContent =
          "Este endereço passou a usar outro banco. Os conteúdos anteriores podem estar no banco vinculado ao deployment anterior. Confira as variáveis de ambiente antes de cadastrar novamente.";
        warning.hidden = false;
      }
      localStorage.setItem("luzia:lastDatabaseId", storage.databaseId);
    } catch {
      /* Browser storage is optional; the database remains authoritative. */
    }
  } catch {
    $("#storage-status").textContent =
      "Não foi possível consultar a identificação do banco.";
  }
}
async function openDashboard() {
  $("#dashboard").hidden = false;
  $("#login").hidden = true;
  $("#password").value = "";
  await loadContents();
  const settings = await api("admin/settings");
  for (const [key, value] of Object.entries(settings)) {
    const input = $("#settings-form").elements[key];
    if (input.type === "checkbox") input.checked = value;
    else input.value = value;
  }
  $("#endpoint").textContent = location.origin + "/api/v1/config";
  await loadStorageStatus();
}
$("#login-form").onsubmit = async (event) => {
  event.preventDefault();
  const button = event.submitter;
  button.disabled = true;
  try {
    const session = await api("admin/login", {
      method: "POST",
      body: JSON.stringify({ password: $("#password").value }),
    });
    csrf = session.csrf;
    $("#login-error").textContent = "";
    await openDashboard();
  } catch (e) {
    $("#login-error").textContent = e.message;
  } finally {
    button.disabled = false;
  }
};
$("#content-form").onsubmit = async (event) => {
  event.preventDefault();
  const form = event.target,
    button = event.submitter;
  const content = Object.fromEntries(
    ["title", "type", "url", "description"].map((k) => [
      k,
      form.elements[k].value,
    ]),
  );
  for (const key of ["published", "primary", "rightsConfirmed"])
    content[key] = form.elements[key].checked;
  button.disabled = true;
  try {
    await api("admin/contents" + (editId ? "/" + editId : ""), {
      method: editId ? "PUT" : "POST",
      body: JSON.stringify(content),
    });
    resetEditor();
    await loadContents();
    message("Conteúdo salvo. A configuração dos apps foi atualizada.");
  } catch (e) {
    message(e.message, true);
  } finally {
    button.disabled = false;
  }
};
$("#settings-form").onsubmit = async (event) => {
  event.preventDefault();
  const form = event.target,
    button = event.submitter;
  button.disabled = true;
  const data = Object.fromEntries(
    ["stationName", "azuracastUrl", "stationId"].map((k) => [
      k,
      form.elements[k].value,
    ]),
  );
  data.recordedOnly = form.elements.recordedOnly.checked;
  try {
    await api("admin/settings", { method: "PUT", body: JSON.stringify(data) });
    message("Configuração salva.");
  } catch (e) {
    message(e.message, true);
  } finally {
    button.disabled = false;
  }
};
$("#type").onchange = updateType;
$("#url").oninput = updateType;
$("#cancel").onclick = resetEditor;
$("#add").onclick = () => {
  resetEditor();
  $("#title").focus();
};
$("#logout").onclick = async () => {
  try {
    await api("admin/logout", { method: "POST" });
    resetEditor();
    showLogin();
  } catch (e) {
    message(e.message, true);
  }
};
for (const button of document.querySelectorAll("[data-view]"))
  button.onclick = () => {
    for (const b of document.querySelectorAll("[data-view]")) {
      const selected = b === button;
      b.classList.toggle("active", selected);
      $("#" + b.dataset.view + "-view").hidden = !selected;
    }
    if (button.dataset.view === "settings") void loadStorageStatus();
  };
(async () => {
  try {
    csrf = (await api("admin/session")).csrf;
    await openDashboard();
  } catch {
    showLogin();
  }
})();
