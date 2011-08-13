class InfobaseReport
  attr_accessor :rows, :row_type
  
  def initialize(rows, row_type)
    @rows = rows
    @row_type = row_type
  end
  
  def self.reports_to_add_semester_stats
    ["Region", "Team", "Ministry Location"]
  end
  
  def get_totals
    unless @totals
      @totals = InfobaseReportRow.new
      Statistic.all_stats.each do |stat_type|
        total = 0
        @rows.each do |row|
          total += row.send(stat_type) if row.send(stat_type)
        end
        @totals.send(stat_type + "=", total)
      end

      # When displaying weekly stats records for a single activity we just want to grab the most recent stats
      if !InfobaseReport.reports_to_add_semester_stats.include?(@row_type)
        Statistic.semester_stats.each do |stat_type|
          total = 0
          last_row = @rows.last
          total = last_row.send(stat_type) if last_row && last_row.send(stat_type)
          @totals.send(stat_type + "=", total)
        end
      end
    end
    @totals
  end
  
  def self.create_national_report(from_date, to_date, strategies)
    rows = []
    Region.standard_region_codes.each do |region|
      stats = start_national_query(from_date, to_date, strategies, region).
        group(TargetArea.table_name + ".region")
      stats = sum_weekly_stats(stats)
      
      last_stats = start_national_query(from_date, to_date, strategies, region).
        group(Statistic.table_name + ".fk_Activity").having("max(" + Statistic.table_name + ".periodEnd)")
      last_stats = sum_semester_stats(stats)
      
      rows << InfobaseReportRow.new(Region.full_name(region), stats.first, last_stats, region)
    end
    InfobaseReport.new(rows, "Region")
  end

  def self.create_regional_report(region, from_date, to_date, strategies)
    rows = []
    teams = Team.active.where("region = ?", region).order(:name)
    teams.each do |team|
      stats = start_regional_query(from_date, to_date, strategies, region, team).
        group(Activity.table_name + ".fk_teamID")
      stats = sum_weekly_stats(stats)
      
      last_stats = start_regional_query(from_date, to_date, strategies, region, team).
        group(Statistic.table_name + ".fk_Activity").having("max(" + Statistic.table_name + ".periodEnd)")
      last_stats = sum_semester_stats(stats)
      
      rows << InfobaseReportRow.new(team.name, stats.first, last_stats, team.id)
    end
    InfobaseReport.new(rows, "Team")
  end
  
  def self.create_team_report(team, from_date, to_date, strategies)
    rows = []
    activities = team.get_activities_for_strategies(strategies)
    activities.each do |activity|
      stats = start_team_query(from_date, to_date, strategies, activity).
        group(Activity.table_name + ".ActivityId")
      stats = sum_weekly_stats(stats)
      
      last_stats = start_team_query(from_date, to_date, strategies, activity).
        group(Statistic.table_name + ".fk_Activity").having("max(" + Statistic.table_name + ".periodEnd)")
      last_stats = sum_semester_stats(stats)
      
      rows << InfobaseReportRow.new(activity.target_area.name, stats.first, last_stats, activity.target_area.id, Activity.strategies[activity.strategy])
    end
    InfobaseReport.new(rows, "Ministry Location")
  end
  
  def self.create_location_reports(location, from_date, to_date, strategies)
    reports = []
    activities = location.get_activities_for_strategies(strategies) # TODO: include inactive activities that have stats between from and to dates
    activities.each do |activity|
      rows = []
      stats = activity.statistics.between_dates(from_date, to_date)
      stats.each do |stat|
        rows << InfobaseReportRow.new(stat.periodBegin.to_s + " - " + stat.periodEnd.to_s, stat, [stat], nil, nil)
      end
      reports << InfobaseReport.new(rows, activity.target_area.name + " - <br/>" + Activity.strategies[activity.strategy])
    end
    reports
  end
  
  private
  
  def self.sum_weekly_stats(stats)
    Statistic.weekly_stats.each do |stat|
      stats = stats.select("SUM(#{stat}) AS #{stat}")
    end
    stats
  end
  
  def self.sum_semester_stats(stats)
    Statistic.semester_stats.each do |stat|
      stats = stats.select("SUM(#{stat}) AS #{stat}")
    end
    stats
  end
  
  def self.start_national_query(from_date, to_date, strategies, region)
    stats = start_stats_query(from_date, to_date)
    stats = add_strategies_clause(stats, strategies)
    stats = add_region_clause(stats, region)
    stats = add_joins(stats)
    stats
  end
  
  def self.start_regional_query(from_date, to_date, strategies, region, team)
    stats = start_national_query(from_date, to_date, strategies, region)
    stats = add_team_clause(stats, team)
    stats
  end
  
  def self.start_team_query(from_date, to_date, strategies, activity)
    stats = start_stats_query(from_date, to_date)
    stats = add_strategies_clause(stats, strategies)
    stats = add_activity_clause(stats, activity)
    stats = add_joins(stats)
    stats
  end
  
  def self.start_stats_query(from_date, to_date)
    Statistic.between_dates(from_date, to_date)
  end
  
  def self.add_joins(relation)
    relation.joins(:activity => :target_area)
  end
  
  def self.add_strategies_clause(relation, strategies)
    relation.where(Activity.table_name + ".strategy IN (?)", strategies)
  end
  
  def self.add_region_clause(relation, region)
    relation.where(TargetArea.table_name + ".region = ?", region)
  end
  
  def self.add_team_clause(relation, team)
    relation.where(Activity.table_name + ".fk_teamID = ?", team.id)
  end
  
  def self.add_activity_clause(relation, activity)
    relation.where(Activity.table_name + ".ActivityId = ?", activity.id)
  end
end