defmodule EexCharts.PDF.Arc do
  @moduledoc """
  SVG elliptical arcs as cubic Béziers.

  PDF has no arc operator — only `c` (cubic Bézier) — so every `A` command in
  a chart's path data has to be re-expressed before it can be drawn. Pies,
  donuts, radial bars and rounded bar corners are all arcs, so this is most of
  the geometry in the library.

  `to_curves/7` implements the conversion the SVG specification describes in
  appendix F.6: the endpoint parameterization the `A` command uses is turned
  into the centre parameterization (centre, both radii, start angle, swept
  angle), which is then split into segments of at most 90° — the widest an
  arc can be approximated by one cubic to within a fraction of a device
  pixel — and each segment gets the standard `4/3 · tan(δ/4)` control-point
  construction.

  Everything here works in the SVG's own coordinate space (y down); the
  caller flips the resulting points.
  """

  @doc """
  Converts one `A rx ry rotation large_arc sweep x2 y2` command, starting from
  the current point `{x1, y1}`, into a list of cubic segments
  `{{c1x, c1y}, {c2x, c2y}, {x, y}}`.

  Degenerate arcs — a zero radius, or an endpoint equal to the start — become
  a single straight segment (the specification says to treat them as a
  `lineto`), so the caller can emit them as curves without a special case.
  """
  def to_curves({x1, y1}, rx, ry, rotation, large_arc, sweep, {x2, y2}) do
    rx = abs(rx * 1.0)
    ry = abs(ry * 1.0)

    if rx == 0.0 or ry == 0.0 or (x1 == x2 and y1 == y2) do
      [line_segment({x1, y1}, {x2, y2})]
    else
      phi = rotation * :math.pi() / 180
      cos_phi = :math.cos(phi)
      sin_phi = :math.sin(phi)

      # Step 1: the endpoints in the ellipse's own (unrotated, origin-centred)
      # frame.
      dx = (x1 - x2) / 2
      dy = (y1 - y2) / 2
      x1p = cos_phi * dx + sin_phi * dy
      y1p = -sin_phi * dx + cos_phi * dy

      # Step 2: scale radii up if they are too small to span the endpoints.
      lambda = x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry)

      {rx, ry} =
        if lambda > 1, do: {rx * :math.sqrt(lambda), ry * :math.sqrt(lambda)}, else: {rx, ry}

      # Step 3: the centre, in that same frame. Both flags together pick which
      # of the two ellipses through the endpoints, and which of its two arcs.
      sign = if large_arc == sweep, do: -1, else: 1

      num = rx * rx * (ry * ry) - rx * rx * (y1p * y1p) - ry * ry * (x1p * x1p)
      den = rx * rx * (y1p * y1p) + ry * ry * (x1p * x1p)
      coef = sign * :math.sqrt(max(num / den, 0.0))

      cxp = coef * rx * y1p / ry
      cyp = -coef * ry * x1p / rx

      cx = cos_phi * cxp - sin_phi * cyp + (x1 + x2) / 2
      cy = sin_phi * cxp + cos_phi * cyp + (y1 + y2) / 2

      # Step 4: start angle and swept angle.
      theta1 = angle(1.0, 0.0, (x1p - cxp) / rx, (y1p - cyp) / ry)

      delta =
        angle(
          (x1p - cxp) / rx,
          (y1p - cyp) / ry,
          (-x1p - cxp) / rx,
          (-y1p - cyp) / ry
        )

      two_pi = 2 * :math.pi()

      delta =
        cond do
          sweep == 0 and delta > 0 -> delta - two_pi
          sweep != 0 and delta < 0 -> delta + two_pi
          true -> delta
        end

      segments = max(ceil(abs(delta) / (:math.pi() / 2)), 1)
      step = delta / segments

      ellipse = {cx, cy, rx, ry, cos_phi, sin_phi}

      Enum.map(0..(segments - 1), fn i ->
        segment(ellipse, theta1 + i * step, step)
      end)
    end
  end

  # A straight run written as a cubic: both controls sit on the line, so the
  # curve is the line.
  defp line_segment({x1, y1}, {x2, y2}) do
    {{x1 + (x2 - x1) / 3, y1 + (y2 - y1) / 3}, {x1 + 2 * (x2 - x1) / 3, y1 + 2 * (y2 - y1) / 3},
     {x2, y2}}
  end

  # One ≤90° piece, from `theta` sweeping `delta`. `alpha` is the classic
  # 4/3·tan(δ/4) tangent length that makes the cubic touch the ellipse at both
  # ends with matching derivatives.
  defp segment({cx, cy, rx, ry, cos_phi, sin_phi}, theta, delta) do
    theta2 = theta + delta
    alpha = 4 / 3 * :math.tan(delta / 4)

    {x1, y1} = point(cx, cy, rx, ry, cos_phi, sin_phi, theta)
    {dx1, dy1} = derivative(rx, ry, cos_phi, sin_phi, theta)
    {x2, y2} = point(cx, cy, rx, ry, cos_phi, sin_phi, theta2)
    {dx2, dy2} = derivative(rx, ry, cos_phi, sin_phi, theta2)

    {{x1 + alpha * dx1, y1 + alpha * dy1}, {x2 - alpha * dx2, y2 - alpha * dy2}, {x2, y2}}
  end

  defp point(cx, cy, rx, ry, cos_phi, sin_phi, theta) do
    ct = :math.cos(theta)
    st = :math.sin(theta)
    {cx + rx * ct * cos_phi - ry * st * sin_phi, cy + rx * ct * sin_phi + ry * st * cos_phi}
  end

  defp derivative(rx, ry, cos_phi, sin_phi, theta) do
    ct = :math.cos(theta)
    st = :math.sin(theta)
    {-rx * st * cos_phi - ry * ct * sin_phi, -rx * st * sin_phi + ry * ct * cos_phi}
  end

  # Signed angle from (ux, uy) to (vx, vy).
  defp angle(ux, uy, vx, vy) do
    dot = ux * vx + uy * vy
    len = :math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
    a = :math.acos((dot / len) |> max(-1.0) |> min(1.0))
    if ux * vy - uy * vx < 0, do: -a, else: a
  end
end
