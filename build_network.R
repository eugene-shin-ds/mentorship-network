# Academic Mentorship Network v2
# Run the complete script in RStudio (R >= 4.0).
# Input names are identifiers. Reconcile aliases and homonyms in Excel first.

packages <- c("readxl", "dplyr", "igraph", "visNetwork", "htmlwidgets",
              "htmltools", "rmarkdown")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) install.packages(missing)
library(dplyr)

# ---- Settings ---------------------------------------------------------------
input_file <- "Family tree Flourish data.xlsx"
sheet_name <- "Family tree links"
output_file <- file.path(getwd(), "index.html")
excluded_preceptors <- c("Smith, Bailey") # Existing exclusion retained.
large_label_min <- 5L                    # >4 direct trainees
normal_font_size <- 14
large_font_size <- 21
base_radius <- 15
size_growth <- 4
maximum_radius <- 35

if (!rmarkdown::pandoc_available()) {
  stop("Pandoc is required for a single HTML file. Run this script in RStudio with Pandoc available.")
}
raw <- readxl::read_excel(input_file, sheet = sheet_name)
names(raw) <- trimws(names(raw))
if (!all(c("Preceptor", "Trainee") %in% names(raw))) {
  stop("Required columns: Preceptor, Trainee")
}
clean_name <- function(x) {
  x <- gsub("\u00A0", " ", as.character(x), fixed = TRUE)
  x <- trimws(gsub("[[:space:]]+", " ", x))
  x[!is.na(x) & x == ""] <- NA_character_
  x
}
cleaned <- raw %>% transmute(
  Preceptor = clean_name(Preceptor), Trainee = clean_name(Trainee)
)
missing_rows <- sum(!complete.cases(cleaned))
excluded_rows <- sum(!is.na(cleaned$Preceptor) &
                      cleaned$Preceptor %in% excluded_preceptors)
links <- cleaned %>% filter(
  !is.na(Preceptor), !is.na(Trainee),
  !(Preceptor %in% excluded_preceptors)
)
duplicate_rows <- nrow(links) - nrow(distinct(links))
links <- distinct(links)
if (!nrow(links)) stop("No complete relationships remain.")
self_links <- filter(links, Preceptor == Trainee)
if (nrow(self_links)) {
  print(self_links)
  stop("Self-relationships found. Correct these rows in Excel first.")
}

# Counts refer to unique people in the retained full dataset, not filtered views.
people <- sort(unique(c(links$Preceptor, links$Trainee)))
edges <- data.frame(id = seq_len(nrow(links)),
                    from = match(links$Preceptor, people),
                    to = match(links$Trainee, people))
nodes <- data.frame(id = seq_along(people), label = people,
                    stringsAsFactors = FALSE)
direct_trainees <- tabulate(edges$from, nbins = nrow(nodes))
direct_preceptors <- tabulate(edges$to, nbins = nrow(nodes))
g <- igraph::graph_from_data_frame(links, directed = TRUE,
                                  vertices = data.frame(name = people))
cycle_present <- !igraph::is_dag(g)
# Reachability works even with cycles. Exclude the starting person and all
# direct trainees; each remaining downstream person is counted only once.
indirect_connections <- vapply(seq_along(people), function(i) {
  reachable <- as.integer(igraph::subcomponent(g, i, mode = "out"))
  direct <- as.integer(igraph::neighbors(g, i, mode = "out"))
  length(setdiff(reachable, c(i, direct)))
}, integer(1))
nodes$group <- ifelse(direct_trainees > 0 & direct_preceptors > 0, "Both",
                      ifelse(direct_trainees > 0, "Mentor only", "Trainee only"))
# Radius increases gently; exact counts remain available in hover information.
nodes$size <- pmin(maximum_radius, base_radius + size_growth * sqrt(direct_trainees))
nodes$font.size <- ifelse(direct_trainees >= large_label_min,
                          large_font_size, normal_font_size)
nodes$title <- paste0(
  "<b>", htmltools::htmlEscape(people), "</b><br>",
  "Role: ", nodes$group, "<br>",
  "Direct trainees: ", direct_trainees, "<br>",
  "Direct preceptors: ", direct_preceptors, "<br>",
  "Additional downstream connections: ", indirect_connections,
  "<br><small>Full retained dataset. Downstream counts exclude self and direct trainees.<br>",
  "Reachability does not establish generation or mentorship impact.</small>"
)

# ---- Network ---------------------------------------------------------------
network <- visNetwork::visNetwork(nodes, edges, width = "100%", height = "72vh") %>%
  visNetwork::visNodes(shape = "dot", borderWidth = 1.5,
    font = list(face = "Arial", color = "#172033", strokeWidth = 3,
                strokeColor = "#FFFFFF")) %>%
  visNetwork::visEdges(arrows = "to", width = 1.2,
    color = list(color = "#94A3B8", highlight = "#111827", hover = "#111827"),
    smooth = list(enabled = TRUE, type = "continuous")) %>%
  visNetwork::visGroups(groupname = "Mentor only",
    color = list(background = "#56B4E9", border = "#0072B2")) %>%
  visNetwork::visGroups(groupname = "Both",
    color = list(background = "#E8B0D2", border = "#A45289")) %>%
  visNetwork::visGroups(groupname = "Trainee only",
    color = list(background = "#CBD5E1", border = "#64748B")) %>%
  visNetwork::visLayout(randomSeed = 42) %>%
  visNetwork::visPhysics(solver = "barnesHut",
    barnesHut = list(gravitationalConstant = -4000, centralGravity = 0.25,
      springLength = 170, springConstant = 0.04, damping = 0.3, avoidOverlap = 0.7),
    stabilization = list(enabled = TRUE, iterations = 1000, fit = TRUE)) %>%
  visNetwork::visInteraction(navigationButtons = TRUE, keyboard = TRUE,
    dragNodes = TRUE, dragView = TRUE, zoomView = TRUE, hover = TRUE,
    tooltipDelay = 150, hideEdgesOnDrag = TRUE)

# ---- Toolbar and legend ----------------------------------------------------
tags <- htmltools::tags
button <- function(id, label) tags$button(id = id, type = "button", label)
legend_item <- function(color, label) tags$span(class = "legend-item",
  tags$span(class = "swatch", style = paste0("background:", color)), label)
role_counts <- table(factor(nodes$group, levels = c("Mentor only", "Both", "Trainee only")))
size_example <- function(n) {
  radius <- min(maximum_radius, base_radius + size_growth * sqrt(n))
  # Display legend at half diagram scale, with the same relative sizes.
  tags$span(class = "legend-item", tags$span(class = "size-dot",
    style = paste0("width:", radius, "px;height:", radius, "px;")), paste(n, "trainees"))
}
toolbar <- tags$div(id = "mn-toolbar",
  tags$style(htmltools::HTML("
    :root {--ink:#192B40;--muted:#536477;--line:#DFE6ED;--accent:#244E70;}
    * {box-sizing:border-box;}
    body {margin:0;padding:24px!important;background:#F3F5F7;font-family:Arial,sans-serif;color:var(--ink);}
    #mn-toolbar {max-width:1600px;margin:0 auto;}
    #mn-toolbar .masthead {display:flex;justify-content:space-between;align-items:center;gap:20px;margin:0 0 22px;}
    #mn-toolbar .eyebrow {font-size:10px;font-weight:700;letter-spacing:2px;text-transform:uppercase;color:var(--muted);margin-bottom:8px;}
    #mn-toolbar h2 {font-size:28px;line-height:1.2;letter-spacing:-0.7px;margin:0;font-weight:600;}
    #mn-toolbar .subtitle {font-size:13px;color:var(--muted);margin-top:9px;}
    #mn-toolbar .header-mark {height:42px;width:42px;display:grid;place-items:center;border:1px solid #CCD8E2;background:#E8EFF5;border-radius:13px;color:var(--accent);font-size:22px;flex-shrink:0;}
    #mn-toolbar .panel {background:#FFFFFF;border:1px solid var(--line);border-radius:14px;box-shadow:0 3px 12px #243B5310;overflow:hidden;}
    #mn-toolbar .control-grid {display:grid;grid-template-columns:minmax(0,1.35fr) minmax(0,1fr);}
    #mn-toolbar .section {padding:18px 20px;min-width:0;}
    #mn-toolbar .section + .section {border-left:1px solid var(--line);background:#FCFDFE;}
    #mn-toolbar .section-label {font-size:11px;letter-spacing:1.1px;text-transform:uppercase;font-weight:700;color:var(--muted);margin:0 0 13px;}
    #mn-toolbar .controls {display:flex;align-items:end;flex-wrap:wrap;gap:10px;}
    #mn-toolbar .field {display:flex;flex:1 1 160px;min-width:0;flex-direction:column;gap:7px;font-size:12px;font-weight:600;}
    #mn-toolbar select,#mn-toolbar input[type=text] {width:100%;min-width:0;height:42px;padding:0 12px;border:1px solid #C7D2DE;border-radius:8px;background:white;color:var(--ink);font-family:inherit;font-size:13px;}
    #mn-toolbar input::placeholder {color:#64748B;}
    #mn-toolbar button {min-height:42px;padding:9px 14px;border:1px solid #C7D2DE;border-radius:8px;background:white;color:var(--ink);font-family:inherit;font-size:12px;font-weight:600;cursor:pointer;white-space:nowrap;}
    #mn-toolbar button:hover {background:#EDF3F8;border-color:#7B96AD;}
    #mn-toolbar #mn-find {background:var(--accent);border-color:var(--accent);color:white;}
    #mn-toolbar #mn-find:hover {background:#183B57;}
    #mn-toolbar button:focus-visible,#mn-toolbar input:focus-visible,#mn-toolbar select:focus-visible,#mn-toolbar summary:focus-visible {outline:3px solid #8FC8EC;outline-offset:3px;}
    #mn-toolbar .legend-strip {display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:14px;padding:14px 20px;border-top:1px solid var(--line);}
    #mn-toolbar .legend {display:flex;flex-wrap:wrap;align-items:center;gap:14px;font-size:11px;color:var(--muted);}
    #mn-toolbar .legend-item {display:inline-flex;align-items:center;gap:7px;white-space:nowrap;}
    #mn-toolbar .swatch {width:11px;height:11px;border-radius:50%;display:inline-block;border:1px solid #64748B;flex-shrink:0;}
    #mn-toolbar .size-dot {background:#E8EDF2;border:1px solid #8C9EAE;border-radius:50%;display:inline-block;flex-shrink:0;}
    #mn-toolbar .legend-caption {font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:0.6px;}
    #mn-toolbar .label-key {padding:6px 9px;background:#F1F5F8;border-radius:6px;}
    #mn-toolbar .viewbar {display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:12px;margin:17px 0 10px;}
    #mn-toolbar .view-actions {display:flex;gap:7px;flex-wrap:wrap;}
    #mn-toolbar .view-actions button {min-height:34px;padding:6px 11px;background:#F8FAFC;font-size:11px;}
    #mn-status {font-size:12px;font-weight:600;line-height:1.5;overflow-wrap:anywhere;padding-left:12px;border-left:3px solid #7C9DB7;flex:1 1 200px;}
    .visNetwork.html-widget {max-width:1600px;margin:0 auto;background:#FFFFFF;border:1px solid var(--line);border-radius:14px;overflow:hidden;box-shadow:0 4px 16px #243B5308;}
    .vis-network:focus {outline:2px solid #8FC8EC;outline-offset:-3px;}
    #mn-footer {max-width:1600px;margin:12px auto 0;color:var(--muted);font-size:11px;line-height:1.65;}
    #mn-footer .footer-row {display:flex;flex-wrap:wrap;justify-content:space-between;align-items:baseline;gap:10px;}
    #mn-footer .credit {white-space:nowrap;color:#536477;}
    #mn-footer .credit strong {color:var(--ink);font-weight:600;}
    #mn-footer details {margin-top:10px;border-top:1px solid var(--line);padding-top:10px;}
    #mn-footer summary {cursor:pointer;font-weight:600;color:#415970;width:fit-content;}
    #mn-footer .notes {max-width:1000px;margin-top:8px;}
    #mn-footer p {margin:5px 0;}
    @media(max-width:1000px) {#mn-toolbar .control-grid {grid-template-columns:1fr;} #mn-toolbar .section + .section {border-left:0;border-top:1px solid var(--line);}}
    @media(max-width:600px) {body {padding:12px!important;} #mn-toolbar h2 {font-size:23px;} #mn-toolbar .masthead {margin-bottom:16px;} #mn-toolbar .section {padding:15px;} #mn-toolbar .legend-strip {padding:14px 15px;} #mn-toolbar .field {flex-basis:100%;} #mn-toolbar .controls button {flex:1;} #mn-toolbar .header-mark {display:none;} #mn-toolbar .legend {gap:10px;} #mn-toolbar .view-actions {width:100%;} #mn-toolbar .view-actions button {flex:1;} #mn-footer .credit {white-space:normal;}}
    @media(prefers-reduced-motion:reduce) {* {scroll-behavior:auto!important;}}
  ")),
  tags$div(class = "masthead",
    tags$div(tags$div(class = "eyebrow", "People & connections"),
      tags$h2("Academic Mentorship Network"),
      tags$div(class = "subtitle", "Explore recorded mentor and trainee relationships.")),
    tags$div(class = "header-mark", `aria-hidden` = "true", "◎")),
  tags$div(class = "panel",
    tags$div(class = "control-grid",
      tags$div(class = "section",
        tags$div(class = "section-label", "Filter relationships"),
        tags$div(class = "controls",
          tags$label(class = "field", "Preceptor / Mentor",
            tags$select(id = "mn-preceptor", tags$option(value = "", "All preceptors"))),
          tags$label(class = "field", "Trainee",
            tags$select(id = "mn-trainee", tags$option(value = "", "All trainees"))),
          button("mn-reset", "Reset filters"))),
      tags$div(class = "section",
        tags$div(class = "section-label", "Find a person"),
        tags$div(class = "controls",
          tags$label(class = "field", "Search the full network",
            tags$input(id = "mn-search", type = "text", list = "mn-names",
              placeholder = "Type or select a name", autocomplete = "off")),
          tags$datalist(id = "mn-names"), button("mn-find", "Find")))),
    tags$div(class = "legend-strip",
      tags$div(class = "legend", tags$span(class = "legend-caption", "Role"),
        legend_item("#56B4E9", paste0("Mentor only (", role_counts[1], ")")),
        legend_item("#E8B0D2", paste0("Mentor & trainee (", role_counts[2], ")")),
        legend_item("#CBD5E1", paste0("Trainee only (", role_counts[3], ")"))),
      tags$div(class = "legend", tags$span(class = "legend-caption", "Circle size"),
        size_example(0), size_example(5), size_example(20),
        tags$span(class = "label-key", paste0("Larger names: ", large_label_min, "+ direct trainees"))))),
  tags$div(class = "viewbar",
    tags$div(id = "mn-status", role = "status", `aria-live` = "polite", "Loading network..."),
    tags$div(class = "view-actions", button("mn-fit", "Fit to screen"),
      button("mn-layout", "Rearrange"), button("mn-freeze", "Freeze layout")))
)
footer <- tags$footer(id = "mn-footer",
  tags$div(class = "footer-row",
    tags$span("Mentor → trainee · Scroll to zoom · Drag to move · Hover for details"),
    tags$span(class = "credit", "Created by ", tags$strong("Eugene Shin"))),
  tags$details(tags$summary("How to read this network & data notes"),
    tags$div(class = "notes",
      tags$p("Arrows: mentor → trainee. Filters show direct relationships; two selections use AND. ",
        "Color, size and hover counts always use the full retained dataset. ",
        "Size increases gently and is capped; it is not proportional to trainee count. ",
        "Scroll to zoom, drag the background to move, or use the navigation buttons below."),
      tags$p(paste0("Data: complete mentor–trainee pairs only; blank entries are not filled down. ",
        "Excluded preceptor(s): ", if (length(excluded_preceptors)) paste(excluded_preceptors, collapse = "; ") else "None", ". ",
        "Roles describe recorded relationships, not career status. Generated ", Sys.Date(), ". ",
        if (cycle_present) "Cycles are present; downstream connections should not be interpreted as generations." else ""))))
)
network <- htmlwidgets::prependContent(network, toolbar)
network <- htmlwidgets::appendContent(network, footer)

# ---- Interactions: all run locally in the saved HTML ------------------------
js_code <- r"(
function(el, x, data) {
  var net = this.network;
  var allNodes = HTMLWidgets.dataframeToD3(data.nodes).map(function(n) {
    n.font = {size: n['font.size'], face: 'Arial', color: '#172033',
              strokeWidth: 3, strokeColor: '#FFFFFF'};
    delete n['font.size'];
    return n;
  });
  var allEdges = HTMLWidgets.dataframeToD3(data.edges);
  var byId = new Map(allNodes.map(function(n) {return [String(n.id), n];}));
  var p = document.getElementById('mn-preceptor');
  var t = document.getElementById('mn-trainee');
  var search = document.getElementById('mn-search');
  var status = document.getElementById('mn-status');
  var names = document.getElementById('mn-names');
  var visible = new Set();
  var positions = {};
  var pendingFocus = null;
  var layoutRunning = false;
  function copy(o) {return JSON.parse(JSON.stringify(o));}
  function fillSelect(select, ids) {
    allNodes.filter(function(n) {return ids.has(String(n.id));})
      .sort(function(a,b) {return a.label.localeCompare(b.label);})
      .forEach(function(n) {
        var opt = document.createElement('option');
        opt.value = String(n.id); opt.textContent = n.label;
        select.appendChild(opt);
      });
  }
  fillSelect(p, new Set(allEdges.map(function(e) {return String(e.from);}))); 
  fillSelect(t, new Set(allEdges.map(function(e) {return String(e.to);}))); 
  allNodes.forEach(function(n) {
    var opt = document.createElement('option'); opt.value = n.label; names.appendChild(opt);
  });
  function savePositions() {
    Object.assign(positions, net.getPositions());
  }
  function fit() {
    if (visible.size) net.fit({animation:{duration:300}});
  }
  function summary() {
    var count = allEdges.filter(function(e) {
      return (!p.value || String(e.from) === p.value) &&
             (!t.value || String(e.to) === t.value);
    }).length;
    status.textContent = visible.size ? visible.size + ' people · ' + count + ' relationships' :
      'No direct relationships match these filters.';
  }
  function focusPerson(id) {
    net.selectNodes([id]);
    net.focus(id, {scale:1.25, animation:{duration:450}});
    status.textContent += ' · Selected: ' + byId.get(String(id)).label;
  }
  function finishLayout() {
    if (!layoutRunning) return;
    layoutRunning = false;
    net.setOptions({physics:{enabled:false}});
    savePositions(); summary();
    if (pendingFocus !== null && visible.has(String(pendingFocus))) {
      var id = pendingFocus; pendingFocus = null; focusPerson(id);
    } else {fit();}
  }
  net.on('stabilizationIterationsDone', finishLayout);
  net.on('stabilized', finishLayout);
  function arrange() {
    if (!visible.size) return;
    layoutRunning = true;
    status.textContent = 'Arranging ' + visible.size + ' people...';
    net.setOptions({physics:{enabled:true}});
    net.stabilize(1000);
  }
  function applyFilters(focusId) {
    pendingFocus = focusId == null ? null : focusId;
    layoutRunning = false;
    net.setOptions({physics:{enabled:false}});
    savePositions();
    var es = allEdges.filter(function(e) {
      return (!p.value || String(e.from) === p.value) &&
             (!t.value || String(e.to) === t.value);
    });
    visible = new Set();
    es.forEach(function(e) {visible.add(String(e.from));visible.add(String(e.to));});
    var ns = allNodes.filter(function(n) {return visible.has(String(n.id));})
      .map(function(n) {
        var out = copy(n);
        if (positions[n.id]) {out.x = positions[n.id].x;out.y = positions[n.id].y;}
        return out;
      });
    net.setData({nodes:ns, edges:es.map(copy)});
    summary();
    if (!visible.size) {pendingFocus = null;return;}
    arrange();
  }
  p.addEventListener('change', function() {applyFilters();});
  t.addEventListener('change', function() {applyFilters();});
  document.getElementById('mn-reset').addEventListener('click', function() {
    p.value = '';t.value = '';search.value = '';applyFilters();
  });
  document.getElementById('mn-fit').addEventListener('click', fit);
  document.getElementById('mn-layout').addEventListener('click', arrange);
  document.getElementById('mn-freeze').addEventListener('click', function() {
    layoutRunning = false;pendingFocus = null;
    net.setOptions({physics:{enabled:false}});
    net.stopSimulation();savePositions();summary();
    status.textContent += ' · Layout frozen (nodes can still be dragged)';
  });
  function findPerson() {
    var q = search.value.trim().toLowerCase();
    if (!q) {status.textContent = 'Type or select a name first.';return;}
    var matches = allNodes.filter(function(n) {return n.label.toLowerCase() === q;});
    if (!matches.length) matches = allNodes.filter(function(n) {return n.label.toLowerCase().includes(q);});
    if (matches.length !== 1) {
      status.textContent = matches.length ? 'Multiple matches. Select a full name from the suggestions.' : 'Name not found.';
      return;
    }
    var n = matches[0];search.value = n.label;
    if (p.value || t.value) {p.value = '';t.value = '';applyFilters(n.id);}
    else if (layoutRunning) {pendingFocus = n.id;}
    else {summary();focusPerson(n.id);}
  }
  document.getElementById('mn-find').addEventListener('click', findPerson);
  search.addEventListener('keydown', function(e) {
    if (e.key === 'Enter') {e.preventDefault();findPerson();}
  });
  applyFilters();
}
)"
network <- htmlwidgets::onRender(network, js_code, data = list(nodes = nodes, edges = edges))
htmlwidgets::saveWidget(network, file = output_file, selfcontained = TRUE,
                        title = "Academic Mentorship Network")
message("Saved: ", normalizePath(output_file, winslash = "/"))
message("People: ", nrow(nodes), "; unique relationships: ", nrow(edges))
message("Rows with missing names: ", missing_rows,
        "; rows matching preceptor exclusions: ", excluded_rows,
        "; duplicate complete relationships removed: ", duplicate_rows)
browseURL(output_file)
