# frozen_string_literal: true

# Wrapped in a module to prevent class leakage
module ActiveRecordBatchConsumerTest
  describe Deimos::ActiveRecordConsumer, 'Batch Consumer' do
    # Create ActiveRecord table and model
    before(:all) do
      ActiveRecord::Base.connection.create_table(:widgets, force: true) do |t|
        t.string(:test_id)
        t.string(:part_one)
        t.string(:part_two)
        t.integer(:some_int)
        t.boolean(:deleted, default: false)
        t.timestamps

        t.index(%i(part_one part_two), unique: true)
      end

      # Sample model
      class Widget < ActiveRecord::Base
        validates :test_id, presence: true

        default_scope -> { where(deleted: false) }
      end

      Widget.reset_column_information
    end

    after(:all) do
      ActiveRecord::Base.connection.drop_table(:widgets)
    end

    prepend_before(:each) do
      stub_const('MyBatchConsumer', consumer_class)
    end

    around(:each) do |ex|
      # Set and freeze example time
      travel_to start do
        ex.run
      end
    end

    # Default starting time
    let(:start) { Time.zone.local(2019, 1, 1, 10, 30, 0) }

    # Basic uncompacted consumer
    let(:consumer_class) do
      Class.new(described_class) do
        schema 'MySchema'
        namespace 'com.my-namespace'
        key_config plain: true
        record_class Widget
        compacted false
      end
    end

    # Helper to get all instances, ignoring default scopes
    def all_widgets
      Widget.unscoped.all
    end

    # Helper to publish a list of messages and call the consumer
    def publish_batch(messages)
      keys = messages.map { |m| m[:key] }
      payloads = messages.map { |m| m[:payload] }

      test_consume_batch(MyBatchConsumer, payloads, keys: keys, call_original: true)
    end

    describe 'consume_batch' do
      SCHEMA_CLASS_SETTINGS.each do |setting, use_schema_classes|
        context "with Schema Class consumption #{setting}" do
          before(:each) do
            Deimos.configure { |config| config.schema.use_schema_classes = use_schema_classes }
          end

          it 'should handle an empty batch' do
            expect { publish_batch([]) }.not_to raise_error
          end

          it 'should create records from a batch' do
            publish_batch(
              [
                { key: 1,
                  payload: { test_id: 'abc', some_int: 3 } },
                { key: 2,
                  payload: { test_id: 'def', some_int: 4 } }
              ]
            )

            expect(all_widgets).
              to match_array(
                [
                  have_attributes(id: 1, test_id: 'abc', some_int: 3, updated_at: start, created_at: start),
                  have_attributes(id: 2, test_id: 'def', some_int: 4, updated_at: start, created_at: start)
                ]
              )
          end

          it 'should handle deleting a record that doesn\'t exist' do
            publish_batch(
              [
                { key: 1,
                  payload: nil }
              ]
            )

            expect(all_widgets).to be_empty
          end

          it 'should handle an update, followed by a delete in the correct order' do
            Widget.create!(id: 1, test_id: 'abc', some_int: 2)

            publish_batch(
              [
                { key: 1,
                  payload: { test_id: 'abc', some_int: 3 } },
                { key: 1,
                  payload: nil }
              ]
            )

            expect(all_widgets).to be_empty
          end

          it 'should handle a delete, followed by an update in the correct order' do
            Widget.create!(id: 1, test_id: 'abc', some_int: 2)

            travel 1.day

            publish_batch(
              [
                { key: 1,
                  payload: nil },
                { key: 1,
                  payload: { test_id: 'abc', some_int: 3 } }
              ]
            )

            expect(all_widgets).
              to match_array(
                [
                  have_attributes(id: 1, test_id: 'abc', some_int: 3, updated_at: Time.zone.now, created_at: Time.zone.now)
                ]
              )
          end

          it 'should handle a double update' do
            Widget.create!(id: 1, test_id: 'abc', some_int: 2)

            travel 1.day

            publish_batch(
              [
                { key: 1,
                  payload: { test_id: 'def', some_int: 3 } },
                { key: 1,
                  payload: { test_id: 'ghi', some_int: 4 } }
              ]
            )

            expect(all_widgets).
              to match_array(
                [
                  have_attributes(id: 1, test_id: 'ghi', some_int: 4, updated_at: Time.zone.now, created_at: start)
                ]
              )
          end

          it 'should handle a double deletion' do
            Widget.create!(id: 1, test_id: 'abc', some_int: 2)

            publish_batch(
              [
                { key: 1,
                  payload: nil },
                { key: 1,
                  payload: nil }
              ]
            )

            expect(all_widgets).to be_empty
          end

          it 'should ignore default scopes' do
            Widget.create!(id: 1, test_id: 'abc', some_int: 2, deleted: true)
            Widget.create!(id: 2, test_id: 'def', some_int: 3, deleted: true)

            publish_batch(
              [
                { key: 1,
                  payload: nil },
                { key: 2,
                  payload: { test_id: 'def', some_int: 5 } }
              ]
            )

            expect(all_widgets).
              to match_array(
                [
                  have_attributes(id: 2, test_id: 'def', some_int: 5)
                ]
              )
          end
        end
      end
    end

    describe 'compacted mode' do
      # Create a compacted consumer
      let(:consumer_class) do
        Class.new(described_class) do
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config plain: true
          record_class Widget

          # :no-doc:
          def deleted_query(_records)
            raise 'Should not have anything to delete!'
          end
        end
      end

      it 'should allow for compacted batches' do
        expect(Widget).to receive(:import!).once.and_call_original

        publish_batch(
          [
            { key: 1,
              payload: nil },
            { key: 2,
              payload: { test_id: 'xyz', some_int: 5 } },
            { key: 1,
              payload: { test_id: 'abc', some_int: 3 } },
            { key: 2,
              payload: { test_id: 'def', some_int: 4 } },
            { key: 3,
              payload: { test_id: 'hij', some_int: 9 } }
          ]
        )

        expect(all_widgets).
          to match_array(
            [
              have_attributes(id: 1, test_id: 'abc', some_int: 3),
              have_attributes(id: 2, test_id: 'def', some_int: 4),
              have_attributes(id: 3, test_id: 'hij', some_int: 9)
            ]
          )
      end
    end

    describe 'batch atomicity' do
      it 'should roll back if there was an exception while deleting' do
        Widget.create!(id: 1, test_id: 'abc', some_int: 2)

        travel 1.day

        expect(Widget.connection).to receive(:delete).and_raise('Some error')

        expect {
          publish_batch(
            [
              { key: 1,
                payload: { test_id: 'def', some_int: 3 } },
              { key: 1,
                payload: nil }
            ]
          )
        }.to raise_error('Some error')

        expect(all_widgets).
          to match_array(
            [
              have_attributes(id: 1, test_id: 'abc', some_int: 2, updated_at: start, created_at: start)
            ]
          )
      end

      it 'should roll back if there was an invalid instance while upserting' do
        Widget.create!(id: 1, test_id: 'abc', some_int: 2) # Updated but rolled back
        Widget.create!(id: 3, test_id: 'ghi', some_int: 3) # Removed but rolled back

        travel 1.day

        expect {
          publish_batch(
            [
              { key: 1,
                payload: { test_id: 'def', some_int: 3 } },
              { key: 2,
                payload: nil },
              { key: 2,
                payload: { test_id: '', some_int: 4 } }, # Empty string is not valid for test_id
              { key: 3,
                payload: nil }
            ]
          )
        }.to raise_error(ActiveRecord::RecordInvalid)

        expect(all_widgets).
          to match_array(
            [
              have_attributes(id: 1, test_id: 'abc', some_int: 2, updated_at: start, created_at: start),
              have_attributes(id: 3, test_id: 'ghi', some_int: 3, updated_at: start, created_at: start)
            ]
          )
      end
    end

    describe 'compound keys' do
      let(:consumer_class) do
        Class.new(described_class) do
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config schema: 'MySchemaCompound_key'
          record_class Widget
          compacted false

          # :no-doc:
          def deleted_query(records)
            keys = records.
              map { |m| record_key(m.key) }.
              reject(&:empty?)

            # Only supported on Rails 5+
            keys.reduce(@klass.none) do |query, key|
              query.or(@klass.unscoped.where(key))
            end
          end
        end
      end

      it 'should consume with compound keys' do
        Widget.create!(test_id: 'xxx', some_int: 2, part_one: 'ghi', part_two: 'jkl')
        Widget.create!(test_id: 'yyy', some_int: 7, part_one: 'mno', part_two: 'pqr')

        publish_batch(
          [
            { key: { part_one: 'abc', part_two: 'def' }, # To be created
              payload: { test_id: 'aaa', some_int: 3 } },
            { key: { part_one: 'ghi', part_two: 'jkl' }, # To be updated
              payload: { test_id: 'bbb', some_int: 4 } },
            { key: { part_one: 'mno', part_two: 'pqr' }, # To be deleted
              payload: nil }
          ]
        )

        expect(all_widgets).
          to match_array(
            [
              have_attributes(test_id: 'aaa', some_int: 3, part_one: 'abc', part_two: 'def'),
              have_attributes(test_id: 'bbb', some_int: 4, part_one: 'ghi', part_two: 'jkl')
            ]
          )
      end
    end

    describe 'no keys' do
      let(:consumer_class) do
        Class.new(described_class) do
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config none: true
          record_class Widget
        end
      end

      it 'should handle unkeyed topics' do
        Widget.create!(test_id: 'xxx', some_int: 2)

        publish_batch(
          [
            { payload: { test_id: 'aaa', some_int: 3 } },
            { payload: { test_id: 'bbb', some_int: 4 } },
            { payload: nil } # Should be ignored. Can't delete with no key
          ]
        )

        expect(all_widgets).
          to match_array(
            [
              have_attributes(test_id: 'xxx', some_int: 2),
              have_attributes(test_id: 'aaa', some_int: 3),
              have_attributes(test_id: 'bbb', some_int: 4)
            ]
          )
      end
    end

    describe 'soft deletion' do
      let(:consumer_class) do
        Class.new(described_class) do
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config plain: true
          record_class Widget
          compacted false

          # Sample customization: Soft delete
          def remove_records(records)
            deleted = deleted_query(records)

            deleted.update_all(
              deleted: true,
              updated_at: Time.zone.now
            )
          end

          # Sample customization: Undelete records
          def record_attributes(payload, key)
            super.merge(deleted: false)
          end
        end
      end

      it 'should mark records deleted' do
        Widget.create!(id: 1, test_id: 'abc', some_int: 2)
        Widget.create!(id: 3, test_id: 'xyz', some_int: 4)
        Widget.create!(id: 4, test_id: 'uvw', some_int: 5, deleted: true)

        travel 1.day

        publish_batch(
          [
            { key: 1,
              payload: nil },
            { key: 1, # Double delete for key 1
              payload: nil },
            { key: 2, # Create 2
              payload: { test_id: 'def', some_int: 3 } },
            { key: 2, # Delete 2
              payload: nil },
            { key: 3, # Update non-deleted
              payload: { test_id: 'ghi', some_int: 4 } },
            { key: 4, # Revive
              payload: { test_id: 'uvw', some_int: 5 } }
          ]
        )

        expect(all_widgets).
          to match_array(
            [
              have_attributes(id: 1, test_id: 'abc', some_int: 2, deleted: true,
                              created_at: start, updated_at: Time.zone.now),
              have_attributes(id: 2, test_id: 'def', some_int: 3, deleted: true,
                              created_at: Time.zone.now, updated_at: Time.zone.now),
              have_attributes(id: 3, test_id: 'ghi', some_int: 4, deleted: false,
                              created_at: start, updated_at: Time.zone.now),
              have_attributes(id: 4, test_id: 'uvw', some_int: 5, deleted: false,
                              created_at: start, updated_at: Time.zone.now)
            ]
          )
      end
    end

    describe 'skipping records' do
      let(:consumer_class) do
        Class.new(described_class) do
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config plain: true
          record_class Widget

          # Sample customization: Skipping records
          def record_attributes(payload, key)
            return nil if payload[:test_id] == 'skipme'

            super
          end
        end
      end

      it 'should allow overriding to skip any unwanted records' do
        publish_batch(
          [
            { key: 1, # Record that consumer can decide to skip
              payload: { test_id: 'skipme' } },
            { key: 2,
              payload: { test_id: 'abc123' } }
          ]
        )

        expect(all_widgets).
          to match_array([have_attributes(id: 2, test_id: 'abc123')])
      end
    end

    describe 'association_list feature for SQLite database' do
      let(:consumer_class) do
        Class.new(described_class) do
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config plain: true
          record_class Widget
          association_list :locales
        end
      end

      it 'should throw NotImplemented error' do
        stub_const('MyBatchConsumer', consumer_class)
        expect {
          publish_batch([{ key: 2, payload: { test_id: 'xyz', some_int: 5, title: 'Widget Title' } }])
        }.to raise_error(Deimos::MissingImplementationError)
      end
    end

  end
end
