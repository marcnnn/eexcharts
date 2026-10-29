defmodule EexCharts.RenderComplexityTest do
  # Render work must grow linearly with the number of points. A per-point
  # `Enum.at/2` on the data makes it quadratic: a 16,000-point smooth line took
  # seconds where it should take tens of milliseconds. Reductions (the BEAM's
  # unit of work) are counted instead of wall time, so the check does not
  # depend on machine speed or load. 4x the points costs about 4x the
  # reductions when rendering is linear; a quadratic path pushes it past 8x.
  use ExUnit.Case, async: true

  @small 2_000
  @large 8_000
  @max_ratio 6

  defp data(n), do: Enum.map(1..n, &rem(&1 * 7919, 1000))
  defp cats(n), do: Enum.map(1..n, &"c#{&1}")

  defp reductions(fun) do
    {:reductions, before} = Process.info(self(), :reductions)
    fun.()
    {:reductions, after_} = Process.info(self(), :reductions)
    after_ - before
  end

  defp ratio(render) do
    reductions(fn -> render.(@small) end)
    small = reductions(fn -> render.(@small) end)
    large = reductions(fn -> render.(@large) end)

    large / small
  end

  defp render(type, series, opts) do
    {:safe, io} = EexCharts.render("c", type, series, opts)
    IO.iodata_length(io)
  end

  test "smooth line with tooltips" do
    r = ratio(fn n -> render(:line, [%{name: "a", data: data(n)}], categories: cats(n)) end)
    assert r < @max_ratio, "4x points cost #{Float.round(r, 1)}x the work"
  end

  test "stacked bars, vertical and horizontal" do
    for horizontal <- [false, true] do
      r =
        ratio(fn n ->
          render(:bar, [%{name: "a", data: data(n)}, %{name: "b", data: data(n)}],
            options: %{chart: %{stacked: true}, plot_options: %{bar: %{horizontal: horizontal}}}
          )
        end)

      assert r < @max_ratio, "horizontal: #{horizontal}: 4x points cost #{Float.round(r, 1)}x"
    end
  end

  test "numeric x-axis taking x from categories" do
    r =
      ratio(fn n ->
        render(:line, [%{name: "a", data: data(n)}],
          categories: Enum.map(1..n, & &1),
          options: %{xaxis: %{type: :numeric}}
        )
      end)

    assert r < @max_ratio, "4x points cost #{Float.round(r, 1)}x the work"
  end

  test "a color per data point" do
    colors = fn n ->
      Enum.map(1..n, &"##{String.pad_leading(Integer.to_string(&1, 16), 6, "0")}")
    end

    for render <- [
          fn n -> render(:pie, data(n), options: %{colors: colors.(n)}) end,
          fn n ->
            render(:bar, [%{name: "a", data: data(n)}],
              options: %{colors: colors.(n), plot_options: %{bar: %{distributed: true}}}
            )
          end
        ] do
      r = ratio(render)
      assert r < @max_ratio, "4x points cost #{Float.round(r, 1)}x the work"
    end
  end

  test "heatmap rows, treemap and pie labels" do
    for render <- [
          fn n -> render(:heatmap, [%{name: "a", data: data(n)}], categories: cats(n)) end,
          fn n -> render(:treemap, [%{data: data(n)}], labels: cats(n)) end,
          fn n -> render(:pie, data(n), labels: cats(n)) end
        ] do
      r = ratio(render)
      assert r < @max_ratio, "4x points cost #{Float.round(r, 1)}x the work"
    end
  end
end
