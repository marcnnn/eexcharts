defmodule EexCharts.CircularTest do
  use ExUnit.Case, async: true

  alias EexCharts.{Config, Renderer}
  alias EexCharts.Charts.{Gauge, Pie, Sector}

  @eps 1.0e-6

  defp render(params) do
    params |> Renderer.render() |> EexCharts.SVG.to_iodata() |> IO.iodata_to_binary()
  end

  # Every element `{:el, tag, attrs, children}` of a tree, flattened.
  defp elements({:el, _tag, _attrs, children} = el), do: [el | elements(children)]
  defp elements(list) when is_list(list), do: Enum.flat_map(list, &elements/1)
  defp elements(_), do: []

  defp with_class(tree, class) do
    for {:el, _, %{class: ^class} = attrs, _} <- elements(tree), do: attrs
  end

  # Vertices of a path command list: move/line targets and arc end points.
  defp vertices(d) do
    d
    |> List.flatten()
    |> Enum.flat_map(fn
      {:move, x, y} -> [{x, y}]
      {:line, x, y} -> [{x, y}]
      {:arc, _, _, _, _, _, x, y} -> [{x, y}]
      _ -> []
    end)
  end

  defp arc_radii(d) do
    for {:arc, rx, _, _, _, _, _, _} <- List.flatten(d), do: rx
  end

  # Polar angle (0 = up, clockwise, degrees in [0, 360)) and radius of a point.
  defp polar_of({x, y}, {cx, cy}) do
    {dx, dy} = {x - cx, y - cy}
    a = :math.atan2(dx, -dy) * 180 / :math.pi()
    {:math.sqrt(dx * dx + dy * dy), if(a < 0, do: a + 360, else: a)}
  end

  # Distance from a point to the ray leaving the centre at `ray` degrees.
  defp ray_distance({rho, phi}, ray) do
    off = abs(norm(phi - ray))
    if off >= 90, do: rho, else: rho * :math.sin(off * :math.pi() / 180)
  end

  defp norm(a) when a > 180, do: norm(a - 360)
  defp norm(a) when a <= -180, do: norm(a + 360)
  defp norm(a), do: a

  defp gauge_tree(series, gauge_opts, extra \\ %{}) do
    cfg = Config.build(:gauge, Map.merge(%{plot_options: %{gauge: gauge_opts}}, extra))
    Gauge.render_chart(cfg, %{series: series, static: true}, "g")
  end

  describe "gauge" do
    test "needle angle maps the value linearly onto the start..end sweep" do
      g = Config.build(:gauge, %{}).plot_options.gauge

      for {v, expected} <- [{0, -90}, {25, -45}, {50, 0}, {100, 90}, {-10, -90}, {140, 90}] do
        assert_in_delta Gauge.value_angle(g, v), expected, @eps
      end

      g = %{g | start_angle: -120, end_angle: 120, min: 50, max: 250}
      assert_in_delta Gauge.value_angle(g, 100), -120 + 240 * 50 / 200, @eps

      # reversed dial (counter-clockwise) still interpolates linearly
      g = %{g | start_angle: 90, end_angle: -90, min: 0, max: 10}
      assert_in_delta Gauge.value_angle(g, 2.5), 45, @eps
    end

    test "the rendered needle tip points at the value's angle" do
      for v <- [0, 13, 50, 87.5, 100] do
        tree = gauge_tree([v], %{start_angle: -135, end_angle: 135})
        [hub] = with_class(tree, "eexcharts-gauge-hub")
        [needle] = with_class(tree, "eexcharts-gauge-needle")
        [_b1, tip, _b2] = vertices(needle.d)

        {_r, angle} = polar_of(tip, {hub.cx, hub.cy})
        assert_in_delta norm(angle - (-135 + 270 * v / 100)), 0, 1.0e-6
      end
    end

    test "bands cover their ranges, with a constant pixel gap between them" do
      gap = 4
      bands = [%{from: 0, to: 30, color: "#0f0"}, %{from: 30, to: 70}, %{from: 70, to: 100}]
      tree = gauge_tree([40], %{bands: bands, band_gap: gap})
      [hub] = with_class(tree, "eexcharts-gauge-hub")
      g = Config.build(:gauge, %{plot_options: %{gauge: %{bands: bands}}}).plot_options.gauge
      paths = with_class(tree, "eexcharts-gauge-band")
      assert length(paths) == 3
      # no track and no value arc when bands are given
      assert with_class(tree, "eexcharts-gauge-track") == []
      assert with_class(tree, "eexcharts-gauge-value") == []

      for {band, attrs} <- Enum.zip(bands, paths) do
        pts = attrs.d |> vertices() |> Enum.map(&polar_of(&1, {hub.cx, hub.cy}))
        a0 = Gauge.value_angle(g, band.from)
        a1 = Gauge.value_angle(g, band.to)

        # every corner is exactly gap/2 from its band boundary ray
        start_d = pts |> Enum.map(&ray_distance(&1, a0)) |> Enum.min()
        end_d = pts |> Enum.map(&ray_distance(&1, a1)) |> Enum.min()
        assert_in_delta start_d, gap / 2, 1.0e-6
        assert_in_delta end_d, gap / 2, 1.0e-6

        # and the band spans the angular range in between
        angles = Enum.map(pts, fn {_r, a} -> norm(a) end)
        assert Enum.min(angles) > a0 and Enum.min(angles) < a0 + 3
        assert Enum.max(angles) < a1 and Enum.max(angles) > a1 - 3
      end
    end

    test "bands are clipped to min..max; a band outside the scale is dropped" do
      bands = [%{from: -50, to: 50, color: "#0f0"}, %{from: 120, to: 150, color: "#f00"}]
      tree = gauge_tree([10], %{bands: bands})
      assert [_] = with_class(tree, "eexcharts-gauge-band")
    end

    test "ticks: amount + 1 majors, minors in between, one label per major" do
      tree = gauge_tree([10], %{max: 50, ticks: %{amount: 5, minor: %{amount: 4}}})
      assert length(with_class(tree, "eexcharts-gauge-tick")) == 6 + 5 * 4

      labels =
        for {:el, "text", %{class: "eexcharts-gauge-tick-label"}, text} <- elements(tree),
            do: IO.iodata_to_binary(text)

      assert labels == ~w(0 10 20 30 40 50)
    end

    test "value arc ends at the value; value formatter and name label" do
      html =
        render(%{
          id: "g1",
          type: :gauge,
          series: [%{name: "Speed", data: [42]}],
          options: %{
            plot_options: %{
              gauge: %{data_labels: %{value: %{formatter: fn v -> "#{v} km/h" end}}}
            }
          }
        })

      assert html =~ "42 km/h"
      assert html =~ ">Speed<"
      assert html =~ "eexcharts-gauge-value"
      refute html =~ "NaN"
    end

    test "degenerate input renders without NaN" do
      for {series, opts} <- [
            {[], %{}},
            {[0], %{min: 10, max: 10}},
            {5, %{start_angle: 0, end_angle: 360}},
            {[50], %{needle: %{show: false}, data_labels: %{show: false}}}
          ] do
        html =
          render(%{
            id: "g",
            type: :gauge,
            series: series,
            options: %{plot_options: %{gauge: opts}}
          })

        assert html =~ "<svg"
        refute html =~ "NaN"
        refute html =~ "Infinity"
      end
    end

    test "the dial stays inside the chart box" do
      for {s, e} <- [{-90, 90}, {-135, 135}, {0, 270}, {-60, 60}] do
        tree =
          gauge_tree([30], %{start_angle: s, end_angle: e}, %{chart: %{width: 400, height: 260}})

        for attrs <- with_class(tree, "eexcharts-gauge-track"),
            {x, y} <- vertices(attrs.d) do
          assert x >= 0 and x <= 400
          assert y >= 0 and y <= 260
        end
      end
    end
  end

  describe "radial bar targets" do
    test "series-level and option targets are merged and placed by value" do
      html =
        render(%{
          id: "rt",
          type: :radial_bar,
          series: [%{name: "A", data: [50], targets: [80]}, %{name: "B", data: [30]}],
          options: %{
            plot_options: %{radial_bar: %{targets: [nil, [25, %{value: 60, color: "#f00"}]]}}
          }
        })

      assert length(String.split(html, ~s(class="eexcharts-radialbar-target"))) == 4
      assert html =~ ~s(stroke="#f00")
    end

    test "marker angle matches the target value and crosses the ring" do
      cfg = Config.build(:radial_bar, %{plot_options: %{radial_bar: %{targets: [25]}}})

      tree =
        EexCharts.Charts.RadialBar.render_chart(cfg, %{series: [40], static: true}, "rt")

      [line] = with_class(tree, "eexcharts-radialbar-target")
      [arc] = with_class(tree, "eexcharts-radialbar-arc")
      # the value arc starts straight above the centre, so its x is the centre x
      [{x0, _y0} | _] = vertices(arc.d)

      # 25% of a 360 sweep from 0 is 90 deg: a horizontal line to the right
      assert_in_delta line.y1, line.y2, 1.0e-6
      assert line.x2 > line.x1
      assert line.x1 > x0
    end

    test "no targets by default; a hidden ring hides its target" do
      refute render(%{id: "r", type: :radial_bar, series: [40, 50]}) =~ "radialbar-target"

      html =
        render(%{
          id: "r",
          type: :radial_bar,
          series: [40, 50],
          hidden_series: [0],
          options: %{plot_options: %{radial_bar: %{targets: [70, 90]}}}
        })

      assert length(String.split(html, ~s(class="eexcharts-radialbar-target"))) == 2
    end
  end

  describe "pie spacing and border radius" do
    defp pie_slices(type, values, pie_opts) do
      cfg = Config.build(type, %{plot_options: %{pie: pie_opts}})
      labels = Enum.map(values, &to_string/1)
      geo = Pie.geometry(cfg, values, labels, 400, 400)
      paths = with_class(Pie.render(cfg, geo), "eexcharts-slice")
      {geo, paths}
    end

    test "the gap between adjacent slice edges is constant (spacing px)" do
      for type <- [:pie, :donut, :polar_area],
          values <- [[44, 55, 13, 43, 22], [80, 15, 5], [1, 1, 1, 1]] do
        spacing = 6
        {geo, paths} = pie_slices(type, values, %{spacing: spacing})
        slices = Enum.filter(geo.slices, &(&1.angle > 0 and &1.r > 0))
        assert length(paths) == length(slices)

        for {s, attrs} <- Enum.zip(slices, paths) do
          pts = attrs.d |> vertices() |> Enum.map(&polar_of(&1, {geo.cx, geo.cy}))
          dists_s = Enum.map(pts, &ray_distance(&1, s.start_angle))
          dists_e = Enum.map(pts, &ray_distance(&1, s.start_angle + s.angle))

          # each straight edge runs exactly spacing/2 from the slice boundary,
          # so two neighbours are always `spacing` apart
          assert_in_delta Enum.min(dists_s), spacing / 2, 1.0e-6
          assert_in_delta Enum.min(dists_e), spacing / 2, 1.0e-6
        end
      end
    end

    test "border radius never exceeds half the slice thickness" do
      for r_in <- [0, 40, 90, 99],
          sweep <- [1, 10, 45, 120, 179, 181, 300],
          rho <- [2, 10, 50, 500],
          inset <- [0, 2] do
        case Sector.build(100, r_in, 0, sweep, inset, rho) do
          nil ->
            :ok

          sec ->
            inner =
              case sec.inner do
                {_, v} -> v
              end

            assert sec.rho <= (100 - inner) / 2 + @eps
            assert sec.rho <= rho
            d = Sector.path(sec, 0, 0)

            for {x, y} <- vertices(d) do
              refute is_nil(x) or is_nil(y)
              assert :math.sqrt(x * x + y * y) <= 100 + @eps
            end

            # fillets use the clamped radius
            assert Enum.all?(arc_radii(d), &(&1 in [100, r_in * 1.0, sec.rho, inset * 1.0]))
        end
      end
    end

    test "rounded corners are tangent to the rim" do
      sec = Sector.build(100, 50, 0, 90, 0, 8)
      assert sec.rho == 8.0
      pts = Sector.path(sec, 0, 0) |> vertices() |> Enum.map(&polar_of(&1, {0, 0}))
      radii = Enum.map(pts, &elem(&1, 0))
      # two rim tangent points on r = 100, two on the inner circle r = 50
      assert Enum.count(radii, &(abs(&1 - 100) < 1.0e-6)) == 2
      assert Enum.count(radii, &(abs(&1 - 50) < 1.0e-6)) == 2
    end

    test "a slice thinner than the gap vanishes; other slices still render" do
      {_geo, paths} = pie_slices(:pie, [1000, 1], %{spacing: 12})
      assert length(paths) == 1
    end

    test "edge cases: all-zero and one slice" do
      {_geo, paths} = pie_slices(:donut, [0, 0, 0], %{spacing: 4, border_radius: 6})
      assert paths == []

      # one slice covers the full circle: nothing to keep apart, plain path
      {_geo, [one]} = pie_slices(:pie, [5], %{spacing: 4, border_radius: 6})
      {_geo, [plain]} = pie_slices(:pie, [5], %{})
      assert one.d == plain.d

      html =
        render(%{
          id: "p",
          type: :donut,
          series: [0, 0],
          options: %{plot_options: %{pie: %{spacing: 4}}}
        })

      refute html =~ "NaN"
    end

    test "defaults keep the original slice paths" do
      cfg = Config.build(:pie, %{})
      assert cfg.plot_options.pie.spacing == 0
      assert cfg.plot_options.pie.border_radius == 0
    end
  end
end
