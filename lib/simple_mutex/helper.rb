# frozen_string_literal: true

require "json"

module SimpleMutex
  class Helper
    LIST_MODES = %i[job batch default all].freeze

    class << self
      def get(lock_key)
        new.get(lock_key)
      end

      def list(**options)
        new.list(**options)
      end
    end

    def get(lock_key)
      raw_data = redis.get(lock_key)

      return if raw_data.nil?

      parsed_data = safe_parse(raw_data)

      {
        key: lock_key,
        value: parsed_data.nil? ? raw_data : parsed_data,
      }
    end

    # rubocop:disable Metrics/MethodLength, Style/HashEachMethods, Performance/CollectionLiteralInLoop
    def list(mode: :default)
      check_mode(mode)

      result = []

      redis.keys.each do |lock_key|
        redis.watch(lock_key) do
          raw_data = redis.get(lock_key)

          unless raw_data.nil?
            parsed_data = safe_parse(raw_data)

            if parsed_data.nil?
              result << { key: lock_key, value: raw_data } if mode == :all
            else
              lock_type = parsed_data&.dig("payload", "type")

              if (mode == :all) ||
                 (lock_type == "Job" && %i[job default].include?(mode)) ||
                 (lock_type == "Batch" && %i[batch default].include?(mode))
                result << { key: lock_key, value: parsed_data }
              end
            end
          end

          redis.unwatch
        end
      end

      result
    end
    # rubocop:enable Metrics/MethodLength, Style/HashEachMethods, Performance/CollectionLiteralInLoop

    private

    def check_mode(mode)
      return if LIST_MODES.include?(mode)
      raise ::SimpleMutex::Error, "invalid mode ( only [:job, :batch, :default, :all] allowed)."
    end

    def redis
      ::SimpleMutex.redis
    end

    def safe_parse(raw_data)
      JSON.parse(raw_data)
    rescue JSON::ParserError
      nil
    end
  end
end
