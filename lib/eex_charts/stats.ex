defmodule EexCharts.Stats do
  @moduledoc """
  Pure statistics helpers behind the `:histogram`, `:violin` and raw-data
  `:box_plot` charts. Every function takes plain lists of numbers; non-numbers
  are ignored. Nothing here is random: the same input always gives the same
  output.

  ## Quantiles

  `quantile/2` uses linear interpolation between order statistics, Hyndman
  and Fan's **type 7**, the default of NumPy (`np.percentile`), R
  (`quantile(type = 7)`) and Excel's `PERCENTILE.INC`: for `n` sorted values
  `x[0..n-1]` the `p` quantile sits at position `h = (n - 1) * p`, and the
  result interpolates between `x[floor(h)]` and `x[floor(h) + 1]`.

  ## Box-plot summary

  `summary/2` returns the five-number summary with Tukey whiskers: the fences
  are `q1 - k * iqr` and `q3 + k * iqr` (`k = 1.5` by default); each whisker
  ends at the most extreme observation inside its fence, and observations
  outside the fences are outliers.

  ## Histogram binning

  `bin_edges/2` produces equal-width bins over the data range. The bin count
  comes from one of:

    * `bins: :auto` (default) — Freedman-Diaconis, falling back to Sturges
      when the interquartile range is 0 (Freedman-Diaconis would then give
      zero-width bins)
    * `bins: :fd` — Freedman-Diaconis, width `2 * IQR * n^(-1/3)`
    * `bins: :sturges` — `log2(n) + 1` bins
    * `bins: :scott` — width `(24 * sqrt(pi) / n)^(1/3) * sd` (population sd)
    * `bins: :sqrt` — `sqrt(n)` bins
    * `bins: k` (integer) — exactly `k` bins
    * `bin_width: w` — bins of width `w`, aligned to multiples of `w`
      (so `bin_width: 5` gives edges at 0, 5, 10, ... rather than starting
      at the minimum); takes precedence over `bins`

  The rules match `numpy.histogram_bin_edges` for the same method names:
  the bin count is `ceil(range / width)` and the edges are evenly spaced from
  the minimum to the maximum. When every value is equal the range is widened
  to `value ± 0.5`. The count is capped at 1000 bins.

  `histogram/2` counts values into those bins with NumPy's convention: every
  bin is half-open `[lo, hi)` except the last, which also includes its right
  edge. `normalize/4` turns counts into `:count`, `:probability` (fraction of
  `n`), `:percent` or `:density` (fraction per unit of x, so the bars'
  area sums to 1), optionally cumulative.

  ## Kernel density estimation

  `kde/3` evaluates a Gaussian kernel density estimate. The default bandwidth
  is Silverman's rule of thumb, `0.9 * min(sd, IQR / 1.34) * n^(-1/5)` (sd is
  the sample standard deviation); `:scott` gives Scott's normal reference
  rule, `1.06 * sd * n^(-1/5)`, and a number is used as the bandwidth as is.
  """

  import Bitwise

  @max_bins 1000

  # ── Basics ────────────────────────────────────────────────────────────────

  @doc "Numeric values of `values`, sorted ascending."
  def sorted(values), do: values |> Enum.filter(&is_number/1) |> Enum.sort()

  @doc "Arithmetic mean, or `nil` for no values."
  def mean(values) do
    case Enum.filter(values, &is_number/1) do
      [] -> nil
      xs -> Enum.sum(xs) / length(xs)
    end
  end

  @doc """
  Standard deviation. `ddof: 1` (default) is the sample standard deviation,
  `ddof: 0` the population one. `nil` when there are not enough values.
  """
  def std(values, opts \\ []) do
    ddof = Keyword.get(opts, :ddof, 1)
    xs = Enum.filter(values, &is_number/1)
    n = length(xs)

    if n - ddof <= 0 do
      nil
    else
      m = Enum.sum(xs) / n
      :math.sqrt(Enum.reduce(xs, 0.0, fn x, acc -> acc + (x - m) * (x - m) end) / (n - ddof))
    end
  end

  @doc """
  The `p` quantile (`0 <= p <= 1`) by linear interpolation (type 7, NumPy's
  default). `nil` for no values.
  """
  def quantile(values, p) do
    case sorted(values) do
      [] -> nil
      xs -> quantile_sorted(List.to_tuple(xs), p)
    end
  end

  defp quantile_sorted(t, p) do
    n = tuple_size(t)
    h = (n - 1) * p
    lo = h |> floor() |> max(0) |> min(n - 1)
    hi = min(lo + 1, n - 1)
    frac = h - lo
    a = elem(t, lo)
    a + frac * (elem(t, hi) - a)
  end

  @doc """
  Five-number summary with Tukey whiskers and outliers.

  Returns `nil` for no values, else a map with `:n`, `:min`, `:max`, `:q1`,
  `:median`, `:q3`, `:iqr`, `:mean`, `:lower` / `:upper` (whisker ends) and
  `:outliers` (sorted). Options: `whisker:` the fence multiple (default `1.5`);
  `whisker: nil` runs the whiskers to the extremes with no outliers.
  """
  def summary(values, opts \\ []) do
    case sorted(values) do
      [] ->
        nil

      xs ->
        t = List.to_tuple(xs)
        q1 = quantile_sorted(t, 0.25)
        med = quantile_sorted(t, 0.5)
        q3 = quantile_sorted(t, 0.75)
        iqr = q3 - q1

        {lower, upper, outliers} =
          case Keyword.get(opts, :whisker, 1.5) do
            k when is_number(k) ->
              lo_fence = q1 - k * iqr
              hi_fence = q3 + k * iqr
              {inside, outliers} = Enum.split_with(xs, &(&1 >= lo_fence and &1 <= hi_fence))
              # The fences always contain q1..q3, which lie between data
              # points, so `inside` is never empty.
              {List.first(inside), List.last(inside), outliers}

            nil ->
              {hd(xs), List.last(xs), []}
          end

        %{
          n: length(xs),
          min: hd(xs),
          max: List.last(xs),
          q1: q1,
          median: med,
          q3: q3,
          iqr: iqr,
          mean: Enum.sum(xs) / length(xs),
          lower: lower,
          upper: upper,
          outliers: outliers
        }
    end
  end

  # ── Histogram ─────────────────────────────────────────────────────────────

  @doc """
  Bin edges for `values` (see the moduledoc for `bins:` / `bin_width:`).
  Returns `[]` for no values, else `k + 1` ascending edges.
  """
  def bin_edges(values, opts \\ []) do
    case sorted(values) do
      [] ->
        []

      xs ->
        {lo, hi} = {hd(xs), List.last(xs)}

        case opts[:bin_width] do
          w when is_number(w) and w > 0 ->
            width_edges(lo, hi, w)

          _ ->
            {first, last} = if lo == hi, do: {lo - 0.5, hi + 0.5}, else: {lo, hi}
            linspace(first, last, bin_count(xs, first, last, Keyword.get(opts, :bins, :auto)))
        end
    end
  end

  defp width_edges(lo, hi, w) do
    start = Float.floor(lo / w) * w
    k = max(ceil_int((hi - start) / w), 1)
    # The last bin is closed, so a maximum sitting exactly on an edge is
    # counted; but a maximum past the last edge (float error) needs a bin.
    k = if start + k * w < hi, do: k + 1, else: k
    k = min(k, @max_bins)
    Enum.map(0..k, &tidy(start + &1 * w))
  end

  defp bin_count(_xs, _first, _last, k) when is_integer(k) and k > 0, do: min(k, @max_bins)

  defp bin_count(xs, first, last, method) do
    n = length(xs)
    ptp = List.last(xs) - hd(xs)

    width =
      case method do
        :sturges -> ptp / (:math.log2(n) + 1)
        :sqrt -> ptp / :math.sqrt(n)
        :scott -> :math.pow(24 * :math.sqrt(:math.pi()) / n, 1 / 3) * (std(xs, ddof: 0) || 0.0)
        :fd -> fd_width(xs)
        _auto -> auto_width(xs, ptp, n)
      end

    if width > 0, do: min(max(ceil_int((last - first) / width), 1), @max_bins), else: 1
  end

  defp fd_width(xs) do
    t = List.to_tuple(xs)
    2.0 * (quantile_sorted(t, 0.75) - quantile_sorted(t, 0.25)) * :math.pow(length(xs), -1 / 3)
  end

  defp auto_width(xs, ptp, n) do
    case fd_width(xs) do
      w when w > 0 -> w
      _ -> ptp / (:math.log2(n) + 1)
    end
  end

  defp linspace(first, last, k) do
    step = (last - first) / k
    Enum.map(0..k, fn i -> if i == k, do: last, else: first + i * step end)
  end

  # Multiples of a decimal width pick up float noise (0.1 * 3); round it off
  # at 12 significant digits so edges print as the numbers a reader expects.
  defp tidy(v) when v == 0, do: 0.0

  defp tidy(v) do
    digits = 12 - ceil_int(:math.log10(abs(v)))
    if digits in 0..15, do: Float.round(v * 1.0, digits), else: v * 1.0
  end

  defp ceil_int(x), do: ceil(x)

  @doc """
  Counts `values` into the bins defined by `edges` (NumPy convention: bins are
  `[lo, hi)`, the last one `[lo, hi]`; values outside the edges are dropped).
  """
  def histogram(_values, edges) when length(edges) < 2, do: []

  def histogram(values, edges) do
    t = List.to_tuple(edges)
    k = tuple_size(t) - 1
    first = elem(t, 0)
    last = elem(t, k)
    empty = Map.new(0..(k - 1), &{&1, 0})

    values
    |> Enum.filter(&(is_number(&1) and &1 >= first and &1 <= last))
    |> Enum.reduce(empty, fn x, acc ->
      Map.update!(acc, bin_index(t, k, first, last, x), &(&1 + 1))
    end)
    |> Enum.sort()
    |> Enum.map(&elem(&1, 1))
  end

  # Edges are evenly spaced, so the bin follows from arithmetic; the two
  # corrections absorb float error at the edges, as NumPy's do.
  defp bin_index(t, k, first, last, x) do
    i = ((x - first) / (last - first) * k) |> floor() |> max(0) |> min(k - 1)

    cond do
      x < elem(t, i) and i > 0 -> i - 1
      x >= elem(t, i + 1) and i < k - 1 -> i + 1
      true -> i
    end
  end

  @doc """
  Normalizes bin `counts` over `edges`. `mode` is `:count`, `:probability`,
  `:percent` or `:density`; with `cumulative: true` the values are running
  totals (a cumulative `:density` is the cumulative probability, since the
  density times the bin width is that bin's probability).
  """
  def normalize(counts, edges, mode, cumulative \\ false) do
    n = Enum.sum(counts)
    widths = edges |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> b - a end)

    counts =
      if cumulative, do: counts |> Enum.scan(&(&1 + &2)), else: counts

    case {mode, n} do
      {_, 0} -> counts
      {:probability, _} -> Enum.map(counts, &(&1 / n))
      {:percent, _} -> Enum.map(counts, &(&1 * 100 / n))
      {:density, _} when cumulative -> Enum.map(counts, &(&1 / n))
      {:density, _} -> Enum.zip_with(counts, widths, fn c, w -> c / (n * w) end)
      _count -> counts
    end
  end

  # ── Kernel density ───────────────────────────────────────────────────────

  @doc """
  Kernel bandwidth for `values`: `:silverman` (default), `:scott`, or a
  positive number (returned unchanged). Degenerate samples (one value, or all
  values equal) get 5% of the value's magnitude (or `1.0` for zero), so a
  constant sample still draws as a narrow bump.
  """
  def bandwidth(values, method \\ :silverman)

  def bandwidth(_values, h) when is_number(h) and h > 0, do: h * 1.0

  def bandwidth(values, method) do
    xs = sorted(values)
    n = length(xs)
    sd = std(xs) || 0.0

    spread =
      case xs do
        [] ->
          0.0

        _ ->
          t = List.to_tuple(xs)
          iqr = quantile_sorted(t, 0.75) - quantile_sorted(t, 0.25)

          case method do
            :scott -> 1.06 / 0.9 * sd
            _ -> silverman_spread(sd, iqr / 1.34)
          end
      end

    if spread > 0 do
      0.9 * spread * :math.pow(n, -0.2)
    else
      degenerate_bandwidth(xs)
    end
  end

  # Silverman's A = min(sd, IQR / 1.34), but a zero IQR (heavily tied data)
  # must not collapse the bandwidth while the sd is still informative.
  defp silverman_spread(sd, a) when sd > 0 and a > 0, do: min(sd, a)
  defp silverman_spread(sd, a), do: max(sd, a)

  defp degenerate_bandwidth([]), do: 1.0
  defp degenerate_bandwidth([x | _]) when x != 0, do: abs(x) * 0.05
  defp degenerate_bandwidth(_), do: 1.0

  @doc """
  Gaussian KDE of `values` at each point of `xs`, with bandwidth `h`:
  `f(x) = 1 / (n * h * sqrt(2 * pi)) * sum(exp(-((x - xi) / h)^2 / 2))`.
  """
  def kde(values, xs, h) when is_list(xs) do
    obs = Enum.filter(values, &is_number/1)
    n = length(obs)

    if n == 0 do
      Enum.map(xs, fn _ -> 0.0 end)
    else
      norm = 1 / (n * h * :math.sqrt(2 * :math.pi()))

      Enum.map(xs, fn x ->
        norm *
          Enum.reduce(obs, 0.0, fn xi, acc ->
            u = (x - xi) / h
            acc + :math.exp(-0.5 * u * u)
          end)
      end)
    end
  end

  @doc """
  A density curve ready to draw: the KDE sampled at `points` evenly spaced
  positions (default 64) from `min - cut * h` to `max + cut * h` (default
  `cut: 2`, so the tails fade out). Options: `bandwidth:` (see
  `bandwidth/2`), `points:`, `cut:`.

  Returns `%{bandwidth: h, points: [{x, density}]}`, or `nil` for no values.
  """
  def density_curve(values, opts \\ []) do
    case sorted(values) do
      [] ->
        nil

      xs ->
        h = bandwidth(xs, Keyword.get(opts, :bandwidth, :silverman))
        cut = Keyword.get(opts, :cut, 2)
        k = max(Keyword.get(opts, :points, 64), 2)
        grid = linspace(hd(xs) - cut * h, List.last(xs) + cut * h, k - 1)
        %{bandwidth: h, points: Enum.zip(grid, kde(xs, grid, h))}
    end
  end

  # ── Jitter ────────────────────────────────────────────────────────────────

  @doc """
  A deterministic pseudo-random number in `[0, 1)` for an integer index: a
  fixed integer hash (the MurmurHash3 32-bit finalizer), so jittered points
  land in the same place on every render.
  """
  def jitter(index) when is_integer(index) do
    h = (index + 1) * 0x9E3779B1 &&& 0xFFFFFFFF
    h = bxor(h, h >>> 16) * 0x85EBCA6B &&& 0xFFFFFFFF
    h = bxor(h, h >>> 13) * 0xC2B2AE35 &&& 0xFFFFFFFF
    h = bxor(h, h >>> 16)
    h / 0x100000000
  end
end
