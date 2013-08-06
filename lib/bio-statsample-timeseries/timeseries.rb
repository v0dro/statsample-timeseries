require 'bio-statsample-timeseries/timeseries/pacf'
module Statsample::TimeSeriesShorthands
  # Creates a new Statsample::TimeSeries object
  # Argument should be equal to TimeSeries.new
  def to_time_series(*args)
    Statsample::TimeSeries::TimeSeries.new(self, :scale, *args)
  end

  alias :to_ts :to_time_series
end

class Array
  include Statsample::TimeSeriesShorthands
end

module Statsample
  module TimeSeries
    # Collection of data indexed by time.
    # The order goes from earliest to latest.
    class TimeSeries < Statsample::Vector
      include Statsample::TimeSeries::Pacf
      # Calculates the autocorrelation coefficients of the series.
      #
      # The first element is always 1, since that is the correlation
      # of the series with itself.
      #
      # Usage:
      #
      #  ts = (1..100).map { rand }.to_time_series
      #
      #  ts.acf   # => array with first 21 autocorrelations
      #  ts.acf 3 # => array with first 3 autocorrelations
      #
      def acf max_lags = nil
        max_lags ||= (10 * Math.log10(size)).to_i

        (0..max_lags).map do |i|
          if i == 0
            1.0
          else
            m = self.mean

            # can't use Pearson coefficient since the mean for the lagged series should
            # be the same as the regular series
            ((self - m) * (self.lag(i) - m)).sum / self.variance_sample / (self.size - 1)
          end
        end
      end

      def pacf(max_lags = nil, method = 'yw')
        #parameters:
        #max_lags => maximum number of lags for pcf
        #method => for autocovariance in yule_walker:
          #'yw' for 'yule-walker unbaised', 'mle' for biased maximum likelihood
          #'ld' for Levinson-Durbin recursion

        max_lags ||= (10 * Math.log10(size)).to_i
        if method.downcase.eql? 'yw' or method.downcase.eql? 'mle'
          Pacf::Pacf.pacf_yw(self, max_lags, method)
        elsif method.downcase == 'ld'
          series = self.acvf
          Pacf::Pacf.levinson_durbin(series, max_lags, true)[2]
        else
          raise "Method presents for pacf are 'yw', 'mle' or 'ld'"
        end
      end


      def ar(n = 1500, k = 1)
        series = Statsample::ARIMA::ARIMA.new
        series.yule_walker(self, n, k)
      end

      def acvf(demean = true, unbiased = false)
        #TODO: change parameters list in opts.merge as suggested by John
        #functionality: computes autocovariance of timeseries data
        #returns: array of autocovariances

        if demean
          demeaned_series = self - self.mean
        else
          demeaned_series = self
        end
        n = self.acf.size
        m = self.mean
        if unbiased
          d = Array.new(self.size, self.size)
        else
          d = ((1..self.size).to_a.reverse)[0..n]
        end


        0.upto(n - 1).map do |i|
          (demeaned_series * (self.lag(i) - m)).sum / d[i]
        end
      end

      def correlate(a, v, mode = 'full')
        #peforms cross-correlation of two series
        #multiarray.correlate2(a, v, 'full')
        if a.size < v.size
          raise("Should have same size!")
        end
        ps = a.size + v.size - 1
        a_padded = Array.new(ps, 0)
        a_padded[0...a.size] = a

        out = (mode.downcase.eql? 'full') ? Array.new(ps) : Array.new(a.size)
        #ongoing
      end
      # Lags the series by k periods.
      #
      # The convention is to set the oldest observations (the first ones
      # in the series) to nil so that the size of the lagged series is the
      # same as the original.
      #
      # Usage:
      #
      #  ts = (1..10).map { rand }.to_time_series
      #           # => [0.69, 0.23, 0.44, 0.71, ...]
      #
      #  ts.lag   # => [nil, 0.69, 0.23, 0.44, ...]
      #  ts.lag 2 # => [nil, nil, 0.69, 0.23, ...]
      #
      def lag k = 1
        return self if k == 0

        dup.tap do |lagged|
          (lagged.size - 1).downto k do |i|
            lagged[i] = lagged[i - k]
          end

          (0...k).each do |i|
            lagged[i] = nil
          end
          lagged.set_valid_data
        end
      end

      # Performs a first difference of the series.
      #
      # The convention is to set the oldest observations (the first ones
      # in the series) to nil so that the size of the diffed series is the
      # same as the original.
      #
      # Usage:
      #
      #  ts = (1..10).map { rand }.to_ts
      #            # => [0.69, 0.23, 0.44, 0.71, ...]
      #
      #  ts.diff   # => [nil, -0.46, 0.21, 0.27, ...]
      #
      def diff
        self - self.lag
      end

      # Calculates a moving average of the series using the provided
      # lookback argument. The lookback defaults to 10 periods.
      #
      # Usage:
      #
      #   ts = (1..100).map { rand }.to_ts
      #            # => [0.69, 0.23, 0.44, 0.71, ...]
      #
      #   # first 9 observations are nil
      #   ts.ma    # => [ ... nil, 0.484... , 0.445... , 0.513 ... , ... ]
      def ma n = 10
        return mean if n >= size

        ([nil] * (n - 1) + (0..(size - n)).map do |i|
          self[i...(i + n)].inject(&:+) / n
        end).to_time_series
      end

      # Calculates an exponential moving average of the series using a
      # specified parameter. If wilder is false (the default) then the EMA
      # uses a smoothing value of 2 / (n + 1), if it is true then it uses the
      # Welles Wilder smoother of 1 / n.
      #
      # Warning for EMA usage: EMAs are unstable for small series, as they
      # use a lot more than n observations to calculate. The series is stable
      # if the size of the series is >= 3.45 * (n + 1)
      #
      # Usage: 
      #
      #   ts = (1..100).map { rand }.to_ts
      #            # => [0.69, 0.23, 0.44, 0.71, ...]
      #
      #   # first 9 observations are nil
      #   ts.ema   # => [ ... nil, 0.509... , 0.433..., ... ]
      def ema n = 10, wilder = false
        smoother = wilder ? 1.0 / n : 2.0 / (n + 1)

        # need to start everything from the first non-nil observation
        start = self.data.index { |i| i != nil }

        # first n - 1 observations are nil
        base = [nil] * (start + n - 1)

        # nth observation is just a moving average
        base << self[start...(start + n)].inject(0.0) { |s, a| a.nil? ? s : s + a } / n

        (start + n).upto size - 1 do |i|
          base << self[i] * smoother + (1 - smoother) * base.last
        end

        base.to_time_series
      end

      # Calculates the MACD (moving average convergence-divergence) of the time
      # series - this is a comparison of a fast EMA with a slow EMA.
      def macd fast = 12, slow = 26, signal = 9
        series = ema(fast) - ema(slow)
        [series, series.ema(signal)]
      end

      # Borrow the operations from Vector, but convert to time series
      def + series
        super.to_a.to_ts
      end

      def - series
        super.to_a.to_ts
      end

      def to_s
        sprintf("Time Series(type:%s, n:%d)[%s]", @type.to_s, @data.size,
                @data.collect{|d| d.nil? ? "nil":d}.join(","))
      end
    end
  end
end
