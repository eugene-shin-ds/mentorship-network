# Academic Mentorship Network

Created by Eugene Shin.

Interactive visualization of recorded preceptor and trainee relationships, with role colors, gently scaled node sizes, search, filters, and navigation controls.

## View

Download `index.html` and open it in a browser. The HTML contains the visualization dependencies and relationship data. It contains real names and mentorship relationships; choose repository visibility accordingly. GitHub source view does not run HTML. GitHub Pages hosting is a separate publishing step.

## Rebuild the HTML in R

Place `Family tree Flourish data.xlsx` in the project root and run the complete `build_network.R` script from that directory in RStudio. The script reads the `Family tree links` sheet and writes `index.html`. It installs missing R packages and needs Pandoc, normally included with RStudio. The original Excel workbook is intentionally not included because other sheets contain contact details.

The supplied HTML is the existing reviewed artifact. The R script was inspected but has not been executed in this environment, so byte-for-byte regeneration is not claimed.

## Export the portrait paper figure

```sh
python -m pip install -r requirements.txt
python render_figure.py
```

The Python script reads the actual node and edge data embedded in `index.html`, computes a network layout, and writes PNG at 600 dpi, SVG, and PDF to `figures/`. The largest component has 190 nodes and 240 directed edges. The figure is 7 by 10 inches, with labels for 34 people who have at least three direct trainees. Labels for five or more direct trainees are larger. Vertical position does not indicate generation or chronology.

The portable Python script passed syntax and embedded-data checks. Full execution of this packaged version was not completed here because plotting dependencies are not installed in the current runtime. The earlier figure workflow was executed and visually reviewed.

## Data scope and audit

The HTML contains 317 named nodes and 331 unique directed relationships. These were compared with the original Excel links sheet. Its 335 complete rows reduce to 332 unique relationships after removing three duplicate rows. The existing exclusion of `Smith, Bailey` as preceptor removes the relationship to `Creech, Erin`, leaving the 331 HTML relationships. No HTML-only relationships were found.

Rows without a preceptor do not establish a relationship. Twelve names without any other recorded relationship are not in the graph. The graph therefore is not a complete list of survey respondents.

Unresolved name variants are retained separately: `Gilbert, Brian` / `Gilbert,Brian`, and `Ooka, Vishal` / `Ooka,Vishal`. Confirm identity before merging. The retained graph has no self-links or directed cycles. Roles and trainee counts describe only the retained dataset.

## Methods

Interactive visualization: R with visNetwork and htmlwidgets; igraph for network calculations. Static paper figure: Python with NetworkX, Matplotlib, and adjustText. The graph layout is computed from relationships, not inferred from an image.

No open source license is assigned yet. Bundled third-party HTML dependencies retain their respective licenses.
