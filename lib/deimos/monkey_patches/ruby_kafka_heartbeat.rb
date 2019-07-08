# frozen_string_literal: true

module Kafka
  class Heartbeat
    def initialize(group:, interval:, instrumenter:)
      @group = group
      @interval = interval
      @last_heartbeat = Time.now
      @instrumenter = instrumenter
    end

    def trigger!
      @instrumenter.instrument('heartbeat.consumer',
                               group_id: @group.group_id,
                               topic_partitions: @group.assigned_partitions) do
                                 @group.heartbeat
                                 @last_heartbeat = Time.now
                               end
    end
  end

  class Client
    def consumer(
        group_id:,
        session_timeout: 30,
        offset_commit_interval: 10,
        offset_commit_threshold: 0,
        heartbeat_interval: 10,
        offset_retention_time: nil,
        fetcher_max_queue_size: 100
      )
      cluster = initialize_cluster

      instrumenter = DecoratingInstrumenter.new(@instrumenter,
                                                group_id: group_id)

      # The Kafka protocol expects the retention time to be in ms.
      retention_time = (offset_retention_time && offset_retention_time * 1_000) || -1

      group = ConsumerGroup.new(
        cluster: cluster,
        logger: @logger,
        group_id: group_id,
        session_timeout: session_timeout,
        retention_time: retention_time,
        instrumenter: instrumenter
      )

      fetcher = Fetcher.new(
        cluster: initialize_cluster,
        group: group,
        logger: @logger,
        instrumenter: instrumenter,
        max_queue_size: fetcher_max_queue_size
      )

      offset_manager = OffsetManager.new(
        cluster: cluster,
        group: group,
        fetcher: fetcher,
        logger: @logger,
        commit_interval: offset_commit_interval,
        commit_threshold: offset_commit_threshold,
        offset_retention_time: offset_retention_time
      )

      heartbeat = Heartbeat.new(
        group: group,
        interval: heartbeat_interval,
        instrumenter: instrumenter
      )

      Consumer.new(
        cluster: cluster,
        logger: @logger,
        instrumenter: instrumenter,
        group: group,
        offset_manager: offset_manager,
        fetcher: fetcher,
        session_timeout: session_timeout,
        heartbeat: heartbeat
      )
    end
  end
end
