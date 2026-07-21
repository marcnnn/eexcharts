defmodule EexCharts.CandlestickTest do
  use ExUnit.Case, async: true

  alias EexCharts.Renderer

  defp render(params) do
    params |> Renderer.render() |> IO.iodata_to_binary()
  end

  test "renders one body and one wick per data point" do
    html =
      render(%{
        id: "c1",
        type: :candlestick,
        series: [
          %{
            name: "OHLC",
            data: [
              [6629, 6650, 6623, 6635],
              [6635, 6640, 6605, 6608]
            ]
          }
        ],
        categories: ~w(a b)
      })

    assert html =~ "<svg"
    # one body rect per candle
    assert length(String.split(html, ~s(class="eexcharts-candlestick"))) == 3
    # one wick per candle
    assert length(String.split(html, ~s(class="eexcharts-candlestick-wick"))) == 3
  end

  test "upward candle uses upward color, downward uses downward color" do
    html =
      render(%{
        id: "c2",
        type: :candlestick,
        series: [
          %{
            name: "OHLC",
            data: [
              # close >= open -> upward
              [10, 20, 5, 15],
              # close < open -> downward
              [15, 20, 5, 10]
            ]
          }
        ]
      })

    assert html =~ "#00B746"
    assert html =~ "#EF403C"
  end

  test "accepts %{x:, y: [o,h,l,c]} map data" do
    html =
      render(%{
        id: "c3",
        type: :candlestick,
        series: [%{name: "OHLC", data: [%{x: "Jan", y: [10, 20, 5, 15]}]}],
        categories: ["Jan"]
      })

    assert html =~ ~s(class="eexcharts-candlestick")
  end

  test "tooltip shows O H L C values and respects y_formatter" do
    html =
      render(%{
        id: "c4",
        type: :candlestick,
        series: [%{name: "OHLC", data: [[6629, 6650, 6623, 6635]]}],
        categories: ["Jan"]
      })

    assert html =~ "O: 6629 H: 6650 L: 6623 C: 6635"

    html2 =
      render(%{
        id: "c5",
        type: :candlestick,
        series: [%{name: "OHLC", data: [[1000, 2000, 500, 1500]]}],
        categories: ["Jan"],
        options: %{tooltip: %{y_formatter: fn v -> "$#{v}" end}}
      })

    assert html2 =~ "O: $1000 H: $2000 L: $500 C: $1500"
  end

  test "nil data points are skipped without crashing" do
    html =
      render(%{
        id: "c6",
        type: :candlestick,
        series: [%{name: "OHLC", data: [[10, 20, 5, 15], nil, [12, 18, 8, 14]]}],
        categories: ~w(a b c)
      })

    # two candles rendered, nil skipped
    assert length(String.split(html, ~s(class="eexcharts-candlestick"))) == 3
  end

  test "on_click adds phx bindings with series and index" do
    html =
      render(%{
        id: "c7",
        type: :candlestick,
        series: [%{name: "OHLC", data: [[10, 20, 5, 15]]}],
        on_click: "candle-clicked"
      })

    assert html =~ ~s(phx-click="candle-clicked")
    assert html =~ ~s(phx-value-index="0")
    assert html =~ ~s(phx-value-series="0")
  end

  test "multiple series draw side by side" do
    html =
      render(%{
        id: "c8",
        type: :candlestick,
        series: [
          %{name: "A", data: [[10, 20, 5, 15]]},
          %{name: "B", data: [[12, 22, 7, 17]]}
        ],
        categories: ["Jan"]
      })

    assert length(String.split(html, ~s(class="eexcharts-candlestick"))) == 3
  end
end
