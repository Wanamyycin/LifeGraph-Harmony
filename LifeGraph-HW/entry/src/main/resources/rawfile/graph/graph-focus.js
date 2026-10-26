function bindGraphFocus(svg, graph, links, drag, primary, border, dark) {
  function focus(id) {
    function adjacent(edge) {
      return edge.source.id === id || edge.target.id === id;
    }

    links
      .attr("stroke", function (edge) {
        var color = edge.color || border;
        if (id === null || !adjacent(edge)) return color;
        if (color === border) return primary;
        return d3.color(color).darker(dark ? -0.8 : 0.65).formatHex();
      })
      .attr("stroke-width", function (edge) {
        return id !== null && adjacent(edge) ? 3 : 2;
      })
      .attr("stroke-opacity", function (edge) {
        return id === null ? 0.5 : adjacent(edge) ? 0.95 : 0.25;
      });
  }

  links.attr("stroke-linecap", "round");
  drag
    .on("start.focus", function (event, node) { focus(node.id); })
    .on("end.focus", function () { focus(null); });
  graph.selectAll(".person-node,.event-node")
    .on("click.focus", function (event, node) { focus(node.id); });
  svg.on("click.focus", function () { focus(null); });
}
