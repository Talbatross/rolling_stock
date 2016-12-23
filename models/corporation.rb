require './models/passer'
require './models/purchaser'
require './models/ownable'

class Corporation < Purchaser
  include Passer
  include Ownable

  CORPORATIONS = %w(Android Bear Eagle Horse Jupiter Orion Saturn Ship Star Wheel).freeze

  attr_reader :name, :president, :share_price, :shares, :bank_shares

  def self.calculate_synergy tier, other_tier
    return 0 unless other_tier

    case tier
    when :red
      1
    when :orange
      other_tier == :red ? 1 : 2
    when :yellow
      other_tier == :orange ? 2 : 4
    when :green
      4
    when :blue
      [:green, :yellow].include?(other_tier) ? 4 : 8
    when :purple
      other_tier == :blue ? 8 : 16
    end
  end

  def initialize name, company, share_price, share_prices, log = nil
    super 0
    raise GameException, "Share price #{share_price.price} taken by #{share_price.corporation.name}" if share_price.corporation
    raise GameException, "Share price #{share_price.price} not valid" unless share_price.valid_range? company

    @name = name
    @president = company.owner
    @companies << company
    @share_price = share_price
    @share_price.corporation = self
    @share_prices = share_prices
    @shares = [Share.president(self)].concat 9.times.map { Share.normal(self) }
    @bank_shares = []
    @log = log || []

    company.owner.companies.delete company
    company.owner = self

    issue_initial_shares
  end

  def id
    @name
  end

  def owner
    @president
  end

  def price
    @share_price.price
  end

  def index
    @share_price.index
  end

  def can_buy_share?
    !@bank_shares.empty?
  end

  def is_bankrupt?
    price.zero? || @companies.empty?
  end

  def buy_share player
    raise GameException, 'Cannot buy share. None available' unless can_buy_share?
    raise GameException, 'Player does not have enough money to buy a share.' if player.cash < next_share_price.price
    swap_share_price next_share_price
    player.cash -= price
    player.shares << @bank_shares.pop
    @log << "#{player.name} buys share of #{name} for $#{price}"
  end

  def can_sell_share? player
    share = player.shares.last
    share && !share.president?
  end

  def sell_share player
    raise GameException, 'Cannot sell share' unless can_sell_share? player
    swap_share_price prev_share_price
    player.cash += price
    @bank_shares << player.shares.pop
    @log << "#{player.name} sells share of #{name} for $#{price}"
  end

  def can_issue_share?
    @shares.size > 0
  end

  def issue_share
    raise GameException, 'Cannot issue share' unless can_issue_share?
    @log << "#{name} issues a share and receives $#{prev_share_price.price}"
    swap_share_price prev_share_price
    @cash += price
    @bank_shares << @shares.shift
  end

  def income tier
    total = super

    synergies = @companies.map { |c| [c.name, c.tier] }.to_h

    @companies.each do |company|
      company.synergies.each do |synergy|
        total += self.class.calculate_synergy company.tier, synergies[synergy]
      end

      synergies.delete company.name
    end

    total
  end

  def pay_dividend amount, players
    raise GameException, 'Dividend must be positive' if amount < 0
    raise GameException, 'Total dividends must be payable with corporation cash' if (shares_issued * amount) > @cash

    @cash -= amount * @bank_shares.size

    dividend_log = String.new "#{name} pays $#{amount} dividends - "

    players.each do |player|
      total = amount * player.shares.count { |share| share.corporation == self }
      @cash -= total
      player.cash += total
      next if total == 0
      dividend_log << " #{player.name} receives #{total}"
    end
    @log << dividend_log

    adjust_share_price
  end

  def book_value
    @cash + @companies.reduce(0) { |p, c| c.value + p }
  end

  def market_cap
    shares_issued * price
  end

  def shares_issued
    10 - @shares.size
  end

  def prev_share_price
    return nil if index == 0
    @share_prices.slice(0..(index - 1)).reverse.find &:unowned?
  end

  def next_share_price
    return nil if index >= @share_prices.size - 1
    @share_prices.slice((index + 1)..-1).find &:unowned?
  end

  def image_url
    "/images/#{name.downcase}-20.png"
  end

  private
  def issue_initial_shares
    company = @companies.first
    value = company.value
    num_shares = (value / price.to_f).ceil
    seed = num_shares * price - value

    @cash = seed
    @president.cash -= seed
    @cash += num_shares * price

    @president.shares.concat @shares.shift(num_shares)
    @bank_shares.concat @shares.shift(num_shares)
    @log << "#{owner.name} forms corporation #{name} with #{company.name} at $#{price} - #{num_shares} shares issued."
  end

  def swap_share_price new_price
    @log << "#{name} changes share price $#{price} to $#{new_price.price}"
    new_price.corporation = self
    @share_price.corporation = nil
    @share_price = new_price
  end

  def above_valuation?
    book_value - market_cap >= 0
  end

  def adjust_share_price
    old_index = index

    if above_valuation?
      swap_share_price next_share_price

      if (index - old_index == 1) && above_valuation?
        @log.pop
        swap_share_price next_share_price
      end
    else
      swap_share_price prev_share_price

      if (old_index - index == 1) && !above_valuation?
        @log.pop
        swap_share_price prev_share_price
      end
    end
  end
end
