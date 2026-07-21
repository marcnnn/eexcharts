defmodule EexCharts.Scale do
  @moduledoc """
  Y-axis scale computation, ported from ApexCharts.js v4.7.0
  `src/modules/Scales.js` (`niceScale`).

  Produces "nice" tick values covering the data range: the step size is
  snapped to a 1/2/5/10 mantissa, free endpoints are expanded to multiples of
  the step, and endpoints within 15% of zero are snapped to zero.
  """

  @js_precision 1.0e-11

  # niceScaleDefaultTicks from Scales.js — values with many divisors,
  # indexed by round(max_ticks / 2).
  @default_ticks [
    1,
    2,
    4,
    4,
    6,
    6,
    6,
    6,
    6,
    6,
    6,
    6,
    6,
    6,
    6,
    6,
    6,
    6,
    12,
    12,
    12,
    12,
    12,
    12,
    12,
    12,
    12,
    24
  ]

  # niceScaleAllowedMagMsd — snaps the most significant digit of the raw
  # step to 1, 2, 5 or 10.
  @allowed_mag_msd [1, 1, 2, 5, 5, 5, 10, 10, 10, 10, 10]

  defstruct ticks: [], nice_min: 0, nice_max: 0, step: 1

  @type t :: %__MODULE__{ticks: [number], nice_min: number, nice_max: number, step: number}

  @doc """
  Computes a nice scale for the data range `[y_min, y_max]`.

  Options:

    * `:min` / `:max` — user-forced endpoints
    * `:tick_amount` — user-forced number of intervals
    * `:step_size` — user-forced step
    * `:svg_height` — chart height used to estimate how many ticks fit
      (defaults to 350, mirroring ApexCharts' `(svgHeight - 100) / 15`)
  """
  @spec nice_scale(number, number, keyword | map) :: t
  def nice_scale(y_min, y_max, opts \\ []) do
    opts = Map.new(opts)
    svg_height = opts[:svg_height] || 350

    max_ticks = max((svg_height - 100) / 15, 2)

    got_min = is_number(opts[:min])
    got_max = is_number(opts[:max])
    got_tick_amount = is_number(opts[:tick_amount])
    got_step_size = is_number(opts[:step_size])

    y_min = if got_min, do: opts[:min], else: y_min
    y_max = if got_max, do: opts[:max], else: y_max

    ticks =
      if got_tick_amount do
        abs(round(opts[:tick_amount]))
      else
        idx = min(round(max_ticks / 2), length(@default_ticks) - 1)
        Enum.at(@default_ticks, idx)
      end

    # All-collapsed / empty data: synthesize a range.
    {y_min, y_max} =
      if not is_number(y_min) or not is_number(y_max) or (y_min == 0 and y_max == 0) do
        min0 = if got_min, do: y_min, else: 0
        max0 = if got_max, do: y_max, else: min0 + ticks
        {min0, max0}
      else
        {y_min, y_max}
      end

    # Sanity: swap inverted, expand degenerate ranges.
    {y_min, y_max} =
      cond do
        y_min > y_max -> {y_max, y_min}
        y_min == y_max and y_min == 0 -> {0, 2}
        y_min == y_max -> {y_min - 1, y_max + 1}
        true -> {y_min, y_max}
      end

    ticks = max(ticks, 1)
    range = abs(y_max - y_min)

    # Snap endpoints within 15% of zero onto zero.
    {y_min, got_min} =
      if not got_min and y_min > 0 and y_min / range < 0.15, do: {0, true}, else: {y_min, got_min}

    {y_max, got_max} =
      if not got_max and y_max < 0 and -y_max / range < 0.15,
        do: {0, true},
        else: {y_max, got_max}

    range = abs(y_max - y_min)

    # Nice step: snap most significant digit to 1/2/5/10.
    raw_step = range / ticks
    mag = floor(:math.log10(raw_step))
    mag_pow = :math.pow(10, mag)
    mag_msd = ceil(raw_step / mag_pow)
    mag_msd = Enum.at(@allowed_mag_msd, min(mag_msd, length(@allowed_mag_msd) - 1))
    step = if got_step_size, do: opts[:step_size] * 1.0, else: mag_msd * mag_pow

    {y_min, y_max, step, tiks} =
      cond do
        got_min and got_max ->
          # Range is fixed; honor tick_amount by dividing the range evenly.
          step = if got_tick_amount or not got_step_size, do: range / ticks, else: step
          {y_min * 1.0, y_max * 1.0, step, round(range / step)}

        got_max ->
          min2 = if got_tick_amount, do: y_max - step * ticks, else: step * ffloor(y_min / step)
          {min2, y_max * 1.0, step, round(abs(y_max - min2) / step)}

        got_min ->
          max2 = if got_tick_amount, do: y_min + step * ticks, else: step * fceil(y_max / step)
          {y_min * 1.0, max2, step, round(abs(max2 - y_min) / step)}

        true ->
          # Both free: expand to step multiples.
          min2 = step * ffloor(y_min / step)
          max2 = step * fceil(y_max / step)
          range2 = abs(max2 - min2)
          tiks = ceil((range2 - @js_precision) / (step + @js_precision))
          tiks = if tiks > 16 and length(prime_factors(tiks)) < 2, do: tiks + 1, else: tiks
          {min2, max2, range2 / tiks, tiks}
      end

    # Too many ticks to fit: thin them out via prime factors.
    {step, _tiks} =
      if tiks > max_ticks and not (got_tick_amount or got_step_size) do
        reduce_ticks(tiks, max_ticks, abs(y_max - y_min), step)
      else
        {step, tiks}
      end

    ticks_list = build_ticks(y_min, y_max, step)

    %__MODULE__{
      ticks: ticks_list,
      nice_min: List.first(ticks_list),
      nice_max: List.last(ticks_list),
      step: step
    }
  end

  defp build_ticks(y_min, y_max, step) do
    err = step * @js_precision

    Stream.iterate(y_min, &(&1 + step))
    |> Enum.take_while(fn v -> v - y_max <= err end)
    |> Enum.map(&strip_number/1)
    |> case do
      [] -> [strip_number(y_min)]
      list -> list
    end
  end

  defp reduce_ticks(tiks, max_ticks, range, _step) do
    factors = prime_factors(tiks)

    reduced =
      Enum.reduce_while(products(factors), nil, fn p, _acc ->
        if tiks / p < max_ticks, do: {:halt, tiks / p}, else: {:cont, nil}
      end)

    case reduced do
      nil -> {range, 1}
      tt -> {range / tt, round(tt)}
    end
  end

  # All products of subsets of the prime factors, ascending.
  defp products(factors) do
    factors
    |> Enum.reduce([1], fn f, acc -> acc ++ Enum.map(acc, &(&1 * f)) end)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.drop(1)
  end

  @doc false
  def prime_factors(n) when n < 2, do: []

  def prime_factors(n), do: prime_factors(n, 2, [])

  defp prime_factors(1, _d, acc), do: Enum.reverse(acc)

  defp prime_factors(n, d, acc) when d * d > n, do: Enum.reverse([n | acc])

  defp prime_factors(n, d, acc) do
    if rem(n, d) == 0 do
      prime_factors(div(n, d), d, [d | acc])
    else
      prime_factors(n, d + 1, acc)
    end
  end

  @doc """
  Rounds to 7 significant digits, removing floating point drift
  (ApexCharts `Utils.stripNumber`).
  """
  def strip_number(v) when is_integer(v), do: v

  def strip_number(v) when is_float(v) do
    stripped =
      v
      |> :erlang.float_to_binary([{:scientific, 6}])
      |> String.to_float()

    if stripped == trunc(stripped) and abs(stripped) < 1.0e15, do: trunc(stripped), else: stripped
  end

  defp ffloor(v), do: :math.floor(v)
  defp fceil(v), do: :math.ceil(v)
end
