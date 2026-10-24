defmodule EexCharts.Charts.Sector do
  @moduledoc """
  Geometry for circular sectors (pie slices, donut segments, gauge bands) with
  an optional constant pixel gap and rounded corners.

  Angles are in degrees, `0` points up and angles grow clockwise (the same
  convention as the pie and radial bar modules).

  ## Gap: inset edges, not an angular gap

  `inset` moves each straight edge of the sector `inset` pixels into the
  sector, parallel to its radial line. Two neighbouring sectors that both use
  `inset = spacing / 2` therefore leave a strip of exactly `spacing` pixels
  between them, the same width at the hub as at the rim. (An angular gap
  would be a wedge: thin at the centre and wide at the rim.)

  The inset edges of a convex sector (sweep up to 180 degrees) meet on the
  bisector at distance `inset / sin(sweep / 2)` from the centre; that point
  replaces the centre as the slice tip, or the inner arc is kept when it lies
  further out. A reflex sector (sweep over 180 degrees) is closed around the
  hub by a small arc of radius `inset`, so the strips of its neighbours stay
  constant-width right up to the centre. A sector too thin to survive its
  inset (`inset >= r * sin(sweep / 2)`) vanishes: `build/6` returns `nil`.

  ## Rounded corners

  Each corner where an arc meets a straight edge gets a fillet of radius
  `corner_radius`, tangent to both. The radius is clamped per sector so the
  shape stays valid:

    * at most half the radial thickness (`(r - inner) / 2`), and
    * small enough that the two outer (and the two inner) fillets do not
      overlap: `(inset + rho) <= (r - rho) * sin(sweep / 2)` and
      `(inset + rho) <= (r_in + rho) * sin(sweep / 2)`.

  The tip of a pie slice (where the edges meet near the centre) stays sharp.
  """

  import EexCharts.SVG, only: [move: 2, line: 2, arc: 7, close: 0]

  @doc """
  Builds the sector outline. Returns `nil` when nothing is left to draw, else
  a map with the clamped `:rho`, the `:inner` kind (`{:arc, r_in}`,
  `{:apex, distance}` or `{:hub, inset}`) and the boundary points (relative to
  the centre): `:outer_start`/`:outer_end` (where the straight edges leave
  the rim, before rounding) and `:edge_start`/`:edge_end` (the straight edge
  ends next to the rim, after rounding).
  """
  def build(r, r_in, start, sweep, inset, corner_radius) do
    inset = max(inset * 1.0, 0.0)
    r_in = max(r_in * 1.0, 0.0)
    s = :math.sin(rad(min(sweep / 2, 90)))

    if sweep <= 0 or r <= 0 or inset >= r * s do
      nil
    else
      finish = start + sweep
      inner = inner_kind(r_in, sweep, s, inset)
      rho = clamp_rho(corner_radius, r, inner, s, inset)

      outer_s = deg(:math.asin(inset / r))

      %{
        r: r,
        start: start,
        sweep: sweep,
        inset: inset,
        rho: rho,
        inner: inner,
        outer_start: pt(r, start + outer_s),
        outer_end: pt(r, finish - outer_s),
        edge_start: edge_point(r - rho, inset, rho, start, 1),
        edge_end: edge_point(r - rho, inset, rho, finish, -1)
      }
    end
  end

  @doc "Path commands for `build/6`'s result centred on `{cx, cy}`; `[]` for `nil`."
  def path(nil, _cx, _cy), do: []

  def path(sec, cx, cy) do
    %{r: r, start: a0, sweep: sweep, inset: d, rho: rho} = sec
    a1 = a0 + sweep

    {phi_s, phi_e} =
      if rho > 0 do
        off = deg(:math.asin((d + rho) / (r - rho)))
        {a0 + off, a1 - off}
      else
        off = deg(:math.asin(d / r))
        {a0 + off, a1 - off}
      end

    t = fn {x, y} -> {cx + x, cy + y} end
    {esx, esy} = t.(sec.edge_start)
    {eex, eey} = t.(sec.edge_end)
    {tsx, tsy} = t.(pt(r, phi_s))
    {tex, tey} = t.(pt(r, phi_e))

    outer = [
      move(esx, esy),
      fillet(rho, tsx, tsy),
      arc(r, r, 0, large(phi_e - phi_s), 1, tex, tey),
      fillet(rho, eex, eey)
    ]

    [outer, inner_path(sec, t, a0, a1), close()]
  end

  defp inner_path(%{inner: {:arc, r_in}, inset: d, rho: rho}, t, a0, a1) do
    {psi, ie_r, ie_off} =
      if rho > 0 do
        li = :math.sqrt(max((r_in + rho) ** 2 - (d + rho) ** 2, 0.0))
        {deg(:math.asin((d + rho) / (r_in + rho))), hypot(li, d), deg(:math.atan2(d, li))}
      else
        off = deg(:math.asin(d / r_in))
        {off, r_in, off}
      end

    {iex_, iey} = t.(pt(ie_r, a1 - ie_off))
    {itex, itey} = t.(pt(r_in, a1 - psi))
    {itsx, itsy} = t.(pt(r_in, a0 + psi))
    {isx, isy} = t.(pt(ie_r, a0 + ie_off))

    [
      line(iex_, iey),
      fillet(rho, itex, itey),
      arc(r_in, r_in, 0, large(a1 - a0 - 2 * psi), 0, itsx, itsy),
      fillet(rho, isx, isy)
    ]
  end

  defp inner_path(%{inner: {:apex, a}}, t, a0, a1) do
    {x, y} = t.(pt(a, a0 + (a1 - a0) / 2))
    [line(x, y)]
  end

  defp inner_path(%{inner: {:hub, d}}, t, a0, a1) do
    {x1, y1} = t.(pt(d, a1 - 90))
    {x2, y2} = t.(pt(d, a0 + 90))
    [line(x1, y1), arc(d, d, 0, large(a1 - a0 - 180), 0, x2, y2)]
  end

  # Where the inner boundary sits: an inner arc if it survives the inset, the
  # intersection of the two inset edges for convex sectors, or a hub arc of
  # radius `inset` for reflex ones.
  defp inner_kind(r_in, sweep, s, inset) do
    cond do
      r_in > 0 and r_in * s > inset -> {:arc, r_in}
      sweep <= 180 -> {:apex, if(inset > 0, do: inset / s, else: 0.0)}
      inset > 0 -> {:hub, inset}
      true -> {:apex, 0.0}
    end
  end

  defp clamp_rho(rho, _r, _inner, _s, _d) when not is_number(rho) or rho <= 0, do: 0.0

  defp clamp_rho(rho, r, inner, s, d) do
    inner_r =
      case inner do
        {:arc, r_in} -> r_in
        {:apex, a} -> a
        {:hub, h} -> h
      end

    limits = [rho, (r - inner_r) / 2, (r * s - d) / (1 + s)]

    limits =
      case inner do
        {:arc, r_in} when s < 1 -> [(r_in * s - d) / (1 - s) | limits]
        _ -> limits
      end

    limits |> Enum.min() |> max(0.0) |> Kernel.*(1.0)
  end

  # End of a straight edge next to the rim: the foot of the fillet centre
  # (at distance `cr` from the centre and `d + rho` from the radial line) on
  # the inset edge. `dir` is +1 for the start edge, -1 for the end edge.
  defp edge_point(cr, d, rho, angle, dir) do
    l = :math.sqrt(max(cr * cr - (d + rho) ** 2, 0.0))
    pt(hypot(l, d), angle + dir * deg(:math.atan2(d, l)))
  end

  defp fillet(rho, _x, _y) when rho <= 0, do: []
  defp fillet(rho, x, y), do: arc(rho, rho, 0, 0, 1, x, y)

  defp large(span), do: if(span > 180, do: 1, else: 0)

  @doc "Point at `radius` and `angle` (degrees, 0 = up, clockwise) relative to the centre."
  def pt(radius, angle) do
    a = rad(angle - 90)
    {radius * :math.cos(a), radius * :math.sin(a)}
  end

  defp hypot(a, b), do: :math.sqrt(a * a + b * b)

  defp rad(d), do: d * :math.pi() / 180
  defp deg(r), do: r * 180 / :math.pi()
end
