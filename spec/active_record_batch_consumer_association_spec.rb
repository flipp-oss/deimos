# frozen_string_literal: true

module ActiveRecordBatchConsumerTest # rubocop:disable Metrics/ModuleLength
  describe Deimos::ActiveRecordConsumer,
           'Batch Consumer with MySQL handling associations',
           :integration,
           db_config: DbConfigs::DB_OPTIONS.second do
    include_context('with DB')

    before(:all) do
      ActiveRecord::Base.connection.create_table(:widgets, force: true) do |t|
        t.string(:test_id)
        t.string(:part_one)
        t.string(:part_two)
        t.integer(:some_int)
        t.string(:bulk_import_id)
        t.boolean(:deleted, default: false)
        t.timestamps

        t.index(%i(part_one part_two), unique: true)
      end

      # create one-to-one association -- Details
      ActiveRecord::Base.connection.create_table(:details, force: true) do |t|
        t.string(:title)
        t.string(:bulk_import_id)
        t.belongs_to(:widget)

        t.index(%i(title), unique: true)
      end

      # Create one-to-many association Locales
      ActiveRecord::Base.connection.create_table(:locales, force: true) do |t|
        t.string(:title)
        t.string(:language)
        t.string(:bulk_import_id)
        t.belongs_to(:widget)

        t.index(%i(widget_id title language), unique: true)
      end

      class Detail < ActiveRecord::Base
        validates :title, presence: true
      end

      class Locale < ActiveRecord::Base
        validates :title, presence: true
        validates :language, presence: true
      end

      # Sample model
      class Widget < ActiveRecord::Base
        has_one :detail
        has_many :locales, dependent: :destroy
        validates :test_id, presence: true

        default_scope -> { where(deleted: false) }
      end

      Widget.reset_column_information
      Detail.reset_column_information
      Locale.reset_column_information
    end

    after(:all) do
      ActiveRecord::Base.connection.drop_table(:widgets)
      ActiveRecord::Base.connection.drop_table(:details)
      ActiveRecord::Base.connection.drop_table(:locales)
    end

    before(:each) do
      ActiveRecord::Base.connection.truncate_tables(%i(widgets details locales))
      Widget.create!(test_id: 'bad_id', some_int: 100) # should not show up
    end

    prepend_before(:each) do
      stub_const('MyBatchConsumer', consumer_class)
      stub_const('ConsumerTest::MyBatchConsumer', consumer_class)
      klass = consumer_class
      col = bulk_import_id_column
      rep = replace_associations
      Karafka::App.routes.redraw do
        topic 'my-topic' do
          consumer klass
          schema 'MySchemaWithTitle'
          namespace 'com.my-namespace'
          key_config plain: true
          bulk_import_id_column col
          replace_associations rep
        end
      end
    end

    # Helper to publish a list of messages and call the consumer
    def publish_batch(messages)
      keys = messages.map { |m| m[:key] }
      payloads = messages.map { |m| m[:payload] }

      test_consume_batch(MyBatchConsumer, payloads, keys: keys)
    end

    let(:bulk_import_id_column) { :bulk_import_id }
    let(:replace_associations) { true }

    let(:consumer_class) do
      klass = Class.new(described_class) do
        cattr_accessor :record_attributes_proc
        cattr_accessor :should_consume_proc
        record_class Widget

        def should_consume?(record, associations)
          if self.should_consume_proc
            case self.should_consume_proc.parameters.size
            when 2
              self.should_consume_proc.call(record, associations)
            else
              self.should_consume_proc.call(record)
            end
          else
            true
          end
        end

        def record_attributes(payload, _key)
          if self.record_attributes_proc
            return self.record_attributes_proc.call(payload)
          end

          {
            test_id: payload['test_id'],
            some_int: payload['some_int'],
            detail: {
              title: payload['title']
            }
          }
        end

        def key_columns(klass)
          case klass.to_s
          when Widget.to_s
            nil
          when Detail.to_s
            %w(title widget_id)
          when Locale.to_s
            %w(widget_id title language)
          else
            []
          end
        end

        def columns(record_class)
          all_cols = record_class.columns.map(&:name)

          case record_class.to_s
          when Widget.to_s
            nil
          when Detail.to_s, Locale.to_s
            all_cols - ['id']
          else
            []
          end
        end
      end
      klass
    end

    context 'when association configured in consumer without model changes' do
      before(:each) do
        ActiveRecord::Base.connection.remove_column(:widgets, :bulk_import_id)
        Widget.reset_column_information
      end

      after(:each) do
        ActiveRecord::Base.connection.add_column(:widgets, :bulk_import_id, :string)
      end

      it 'should raise error when bulk_import_id is not found' do
        expect {
          publish_batch([{ key: 2,
                           payload: { test_id: 'xyz', some_int: 5, title: 'Widget Title' } }])
        }.to raise_error('Create bulk_import_id on the widgets table. Run rails g deimos:bulk_import_id {table}'\
        ' to create the migration.')
      end
    end

    context 'with one-to-one relation in association and custom bulk_import_id' do
      let(:bulk_import_id_column) { :custom_id }
      let(:replace_associations) { false }

      before(:all) do
        ActiveRecord::Base.connection.add_column(:widgets, :custom_id, :string, if_not_exists: true)
        Widget.reset_column_information
      end

      it 'should save item to widget and associated detail' do
        publish_batch([{ key: 2,
                         payload: { test_id: 'xyz', some_int: 5, title: 'Widget Title' } }])
        expect(Widget.count).to eq(2)
        expect(Detail.count).to eq(1)
        expect(Widget.last.id).to eq(Detail.first.widget_id)
      end
    end

    context 'with one-to-many relationship in association and default bulk_import_id' do
      let(:replace_associations) { false }
      before(:each) do
        consumer_class.record_attributes_proc = proc do |payload|
          {
            test_id: payload['test_id'],
            some_int: payload['some_int'],
            locales: [
              {
                title: payload['title'],
                language: 'en'
              },
              {
                title: payload['title'],
                language: 'fr'
              }
            ]
          }
        end
      end

      it 'should save item to widget and associated details' do
        publish_batch([{ key: 2,
                         payload: { test_id: 'xyz', some_int: 5, title: 'Widget Title' } }])
        expect(Widget.count).to eq(2)
        expect(Locale.count).to eq(2)
        expect(Widget.last.id).to eq(Locale.first.widget_id)
        expect(Widget.last.id).to eq(Locale.second.widget_id)

        # publish again - should add locales to the widget
        publish_batch([{ key: 2,
                         payload: { test_id: 'xyz', some_int: 7, title: 'Widget Title 2' } }])
        expect(Widget.count).to eq(2)
        expect(Widget.last.some_int).to eq(7)
        expect(Locale.count).to eq(4)
        expect(Locale.all.map(&:widget_id).uniq).to eq([Widget.last.id])
      end
    end

    context 'with replace_associations on' do
      let(:replace_associations) { true }
      before(:each) do
        consumer_class.record_attributes_proc = proc do |payload|
          {
            test_id: payload['test_id'],
            some_int: payload['some_int'],
            locales: [
              {
                title: payload['title'],
                language: 'en'
              },
              {
                title: payload['title'],
                language: 'fr'
              }
            ]
          }
        end
      end

      it 'should save item to widget and replace associated details' do
        publish_batch([{ key: 2,
                         payload: { test_id: 'xyz', some_int: 5, title: 'Widget Title' } }])
        expect(Widget.count).to eq(2)
        expect(Locale.count).to eq(2)
        expect(Widget.last.id).to eq(Locale.first.widget_id)
        expect(Widget.last.id).to eq(Locale.second.widget_id)

        # publish again - should replace locales
        publish_batch([{ key: 2,
                         payload: { test_id: 'xyz', some_int: 7, title: 'Widget Title 2' } }])
        expect(Widget.count).to eq(2)
        expect(Widget.last.some_int).to eq(7)
        expect(Locale.count).to eq(2)
        expect(Locale.all.map(&:title).uniq).to contain_exactly('Widget Title 2')
        expect(Locale.all.map(&:widget_id).uniq).to contain_exactly(Widget.last.id)
      end
    end

    context 'with invalid models' do
      before(:each) do
        consumer_class.should_consume_proc = proc { |record| record.some_int <= 10 }
      end

      it 'should only save valid models' do
        publish_batch([{ key: 2,
                         payload: { test_id: 'xyz', some_int: 5, title: 'Widget Title' } },
                       { key: 3,
                         payload: { test_id: 'abc', some_int: 15, title: 'Widget Title 2' } }])
        expect(Widget.count).to eq(2)
      end
    end

    context 'with invalid associations' do

      before(:each) do
        consumer_class.should_consume_proc = proc { |record, associations|
          record.some_int <= 10 && associations['detail']['title'] != 'invalid'
        }
      end

      it 'should only save valid associations' do
        publish_batch([
                        { key: 2,
                          payload: { test_id: 'xyz', some_int: 5, title: 'valid' } },
                        { key: 3,
                          payload: { test_id: 'abc', some_int: 15, title: 'valid' } },
                        { key: 4,
                          payload: { test_id: 'abc', some_int: 9, title: 'invalid' } }
                      ])
        expect(Widget.count).to eq(2)
        expect(Widget.second.some_int).to eq(5)
      end
    end
           end
end
