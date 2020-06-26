# frozen_string_literal: true

module Deimos
  # ActiveRecord class to record the last time we polled the database.
  # For use with DbPoller.
  class PollInfo < ActiveRecord::Base
    self.table_name = 'deimos_poll_info'
  end
end
