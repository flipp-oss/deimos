# frozen_string_literal: true

RSpec.describe Deimos::ActiveRecordConsume::MassUpdater do

    before(:all) do
      ActiveRecord::Base.connection.create_table(:widgets, force: true) do |t|
        t.string(:test_id)
        t.integer(:some_int)
        t.string(:bulk_import_id)
        t.timestamps
      end

      # create one-to-one association -- Details
      ActiveRecord::Base.connection.create_table(:details, force: true) do |t|
        t.string(:title)
        t.string(:bulk_import_id)
        t.belongs_to(:widget)

        t.index(%i(title), unique: true)
      end
    end

    after(:all) do
      ActiveRecord::Base.connection.drop_table(:widgets)
      ActiveRecord::Base.connection.drop_table(:details)
    end

    let(:detail_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = 'details'
        belongs_to :widget
      end
    end

    let(:widget_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = 'widgets'
        has_one :detail
      end
    end

    let(:bulk_id_generator) { proc { SecureRandom.uuid } }

    before(:each) do
      stub_const('Widget', widget_class)
      stub_const('Detail', detail_class)
      Widget.reset_column_information
    end

    describe '#mass_update' do
      let(:batch) do
        Deimos::ActiveRecordConsume::BatchRecordList.new(
          [
            Deimos::ActiveRecordConsume::BatchRecord.new(
              klass: Widget,
              attributes: { test_id: 'id1', some_int: 5, detail: { title: 'Title 1' } },
              bulk_import_column: 'bulk_import_id',
              bulk_import_id_generator: bulk_id_generator
            ),
            Deimos::ActiveRecordConsume::BatchRecord.new(
              klass: Widget,
              attributes: { test_id: 'id2', some_int: 10, detail: { title: 'Title 2' } },
              bulk_import_column: 'bulk_import_id',
              bulk_import_id_generator: bulk_id_generator
            )
          ]
        )
      end

      it 'should mass update the batch' do
        allow(SecureRandom).to receive(:uuid).and_return('1', '2')
        results = described_class.new(Widget, bulk_import_id_generator: bulk_id_generator).mass_update(batch)
        expect(results.count).to eq(2)
        expect(results.map(&:test_id)).to match(%w(id1 id2))
        expect(Widget.count).to eq(2)
        expect(Widget.all.to_a.map(&:bulk_import_id)).to match(%w(1 2))
        expect(Detail.count).to eq(2)
        expect(Widget.first.detail).not_to be_nil
        expect(Widget.last.detail).not_to be_nil
      end

      context 'with deadlock retries' do
        before(:each) do
          allow(Deimos::Utils::DeadlockRetry).to receive(:sleep)
        end

        it 'should upsert rows after deadlocks' do
          allow(Widget).to receive(:import!).and_raise(
            ActiveRecord::Deadlocked.new('Lock wait timeout exceeded')
          ).twice.ordered
          allow(Widget).to receive(:import!).and_raise(
            ActiveRecord::Deadlocked.new('Lock wait timeout exceeded')
          ).once.and_call_original

          results = described_class.new(Widget, bulk_import_id_generator: bulk_id_generator).mass_update(batch)
          expect(results.count).to eq(2)
          expect(results.map(&:test_id)).to match(%w(id1 id2))
          expect(Widget.count).to eq(2)
          expect(Detail.count).to eq(2)
          expect(Widget.first.detail).not_to be_nil
          expect(Widget.last.detail).not_to be_nil
        end

        it 'should not upsert after encountering multiple deadlocks' do
          allow(Widget).to receive(:import!).and_raise(
            ActiveRecord::Deadlocked.new('Lock wait timeout exceeded')
          ).exactly(3).times
          expect {
            described_class.new(Widget, bulk_import_id_generator: bulk_id_generator).mass_update(batch)
          }.to raise_error(ActiveRecord::Deadlocked)
          expect(Widget.count).to eq(0)
          expect(Detail.count).to eq(0)
        end

      end

      context 'with save_associations_first' do
        before(:all) do
          ActiveRecord::Base.connection.create_table(:fidgets, force: true) do |t|
            t.string(:test_id)
            t.integer(:some_int)
            t.string(:bulk_import_id)
            t.timestamps
          end

          ActiveRecord::Base.connection.create_table(:fidget_details, force: true) do |t|
            t.string(:title)
            t.string(:bulk_import_id)
            t.belongs_to(:fidget)

            t.index(%i(title), unique: true)
          end

          ActiveRecord::Base.connection.create_table(:widget_fidgets, force: true, id: false) do |t|
            t.belongs_to(:fidget)
            t.belongs_to(:widget)
            t.string(:bulk_import_id)
            t.string(:note)
            t.index(%i(widget_id fidget_id), unique: true)
          end
        end

        after(:all) do
          ActiveRecord::Base.connection.drop_table(:fidgets)
          ActiveRecord::Base.connection.drop_table(:fidget_details)
          ActiveRecord::Base.connection.drop_table(:widget_fidgets)
        end

        let(:fidget_detail_class) do
          Class.new(ActiveRecord::Base) do
            self.table_name = 'fidget_details'
            belongs_to :fidget
          end
        end

        let(:fidget_class) do
          Class.new(ActiveRecord::Base) do
            self.table_name = 'fidgets'
            has_one :fidget_detail
          end
        end

        let(:widget_fidget_class) do
          Class.new(ActiveRecord::Base) do
            self.table_name = 'widget_fidgets'
            belongs_to :fidget
            belongs_to :widget
          end
        end

        let(:bulk_id_generator) { proc { SecureRandom.uuid } }

        let(:key_proc) do
          lambda do |klass|
            case klass.to_s
            when 'Widget', 'Fidget'
              %w(id)
            when 'WidgetFidget'
              %w(widget_id fidget_id)
            when 'FidgetDetail', 'Detail'
              %w(title)
            else
              raise "Key Columns for #{klass} not defined"
            end

          end
        end

        before(:each) do
          stub_const('Fidget', fidget_class)
          stub_const('FidgetDetail', fidget_detail_class)
          stub_const('WidgetFidget', widget_fidget_class)
          Widget.reset_column_information
          Fidget.reset_column_information
          WidgetFidget.reset_column_information
        end

        # rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
        it 'should backfill the associations when upserting primary records' do
          batch = Deimos::ActiveRecordConsume::BatchRecordList.new(
            [
              Deimos::ActiveRecordConsume::BatchRecord.new(
                klass: WidgetFidget,
                attributes: {
                  widget: { test_id: 'id1', some_int: 10, detail: { title: 'Widget Title 1' } },
                  fidget: { test_id: 'id1', some_int: 10, fidget_detail: { title: 'Fidget Title 1' } },
                  note: 'Stuff 1'
                },
                bulk_import_column: 'bulk_import_id',
                bulk_import_id_generator: bulk_id_generator
              ),
              Deimos::ActiveRecordConsume::BatchRecord.new(
                klass: WidgetFidget,
                attributes: {
                  widget: { test_id: 'id2', some_int: 20, detail: { title: 'Widget Title 2' } },
                  fidget: { test_id: 'id2', some_int: 20, fidget_detail: { title: 'Fidget Title 2' } },
                  note: 'Stuff 2'
                },
                bulk_import_column: 'bulk_import_id',
                bulk_import_id_generator: bulk_id_generator
              )
            ]
          )

          results = described_class.new(WidgetFidget,
                                        bulk_import_id_generator: bulk_id_generator,
                                        bulk_import_id_column: 'bulk_import_id',
                                        key_col_proc: key_proc,
                                        save_associations_first: true).mass_update(batch)
          expect(results.count).to eq(2)
          expect(Widget.count).to eq(2)
          expect(Detail.count).to eq(2)
          expect(Fidget.count).to eq(2)
          expect(FidgetDetail.count).to eq(2)

          WidgetFidget.all.each_with_index do |widget_fidget, ind|
            widget = Widget.find_by(id: widget_fidget.widget_id)
            expect(widget.test_id).to eq("id#{ind + 1}")
            expect(widget.some_int).to eq((ind + 1) * 10)
            detail = Detail.find_by(widget_id: widget_fidget.widget_id)
            expect(detail.title).to eq("Widget Title #{ind + 1}")
            fidget = Fidget.find_by(id: widget_fidget.fidget_id)
            expect(fidget.test_id).to eq("id#{ind + 1}")
            expect(fidget.some_int).to eq((ind + 1) * 10)
            fidget_detail = FidgetDetail.find_by(fidget_id: widget_fidget.fidget_id)
            expect(fidget_detail.title).to eq("Fidget Title #{ind + 1}")
            expect(widget_fidget.note).to eq("Stuff #{ind + 1}")
          end
        end
        # rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength

      end

      context 'with recorded primary_keys' do
        before(:all) do
          ActiveRecord::Base.connection.create_table(:fidgets, force: true, id: false) do |t|
            t.string :test_id, primary_key: true
            t.integer(:some_int)
            t.string(:bulk_import_id)
            t.timestamps
          end

          ActiveRecord::Base.connection.create_table(:fidget_details, force: true) do |t|
            t.string(:title)
            t.string(:bulk_import_id)
            t.belongs_to(:fidget)

            t.index(%i(title), unique: true)
          end

        end

        after(:all) do
          ActiveRecord::Base.connection.drop_table(:fidgets)
          ActiveRecord::Base.connection.drop_table(:fidget_details)
        end

        let(:fidget_detail_class) do
          Class.new(ActiveRecord::Base) do
            self.table_name = 'fidget_details'
            belongs_to :fidget
          end
        end

        let(:fidget_class) do
          Class.new(ActiveRecord::Base) do
            self.table_name = 'fidgets'
            has_one :fidget_detail
          end
        end

        let(:bulk_id_generator) { proc { SecureRandom.uuid } }

        let(:key_proc) do
          lambda do |klass|
            case klass.to_s
            when 'Fidget'
              %w(test_id)
            when 'FidgetDetail'
              %w(title)
            else
              raise "Key Columns for #{klass} not defined"
            end

          end
        end

        before(:each) do
          stub_const('Fidget', fidget_class)
          stub_const('FidgetDetail', fidget_detail_class)
          Fidget.reset_column_information
        end


        let(:batch) do
          Deimos::ActiveRecordConsume::BatchRecordList.new(
          [
            Deimos::ActiveRecordConsume::BatchRecord.new(
              klass: Fidget,
              attributes: { test_id: 'id1', some_int: 5, fidget_detail: { title: 'Title 1' } },
              bulk_import_column: 'bulk_import_id',
              bulk_import_id_generator: bulk_id_generator
            ),
            Deimos::ActiveRecordConsume::BatchRecord.new(
              klass: Fidget,
              attributes: { test_id: 'id2', some_int: 10, fidget_detail: { title: 'Title 2' } },
              bulk_import_column: 'bulk_import_id',
              bulk_import_id_generator: bulk_id_generator
            )
          ]
        )
        end

        it 'should not backfill the primary key when the primary_key exists' do
          allow(Fidget).to receive(:where).and_call_original
          results = described_class.new(Widget,
                                        bulk_import_id_generator: bulk_id_generator,
                                        bulk_import_id_column: 'bulk_import_id',
                                        key_col_proc: key_proc).mass_update(batch)
          expect(results.count).to eq(2)
          expect(Fidget.count).to eq(2)
          expect(Fidget).not_to have_received(:where).with(:bulk_import_id => [instance_of(String), instance_of(String)])
        end

      end

      context 'without recorded primary_keys' do
        before(:all) do
          ActiveRecord::Base.connection.create_table(:fidgets, force: true) do |t|
            t.string(:test_id)
            t.integer(:some_int)
            t.string(:bulk_import_id)
            t.timestamps
          end

          ActiveRecord::Base.connection.create_table(:fidget_details, force: true) do |t|
            t.string(:title)
            t.string(:bulk_import_id)
            t.belongs_to(:fidget)

            t.index(%i(title), unique: true)
          end

        end

        after(:all) do
          ActiveRecord::Base.connection.drop_table(:fidgets)
          ActiveRecord::Base.connection.drop_table(:fidget_details)
        end

        let(:fidget_detail_class) do
          Class.new(ActiveRecord::Base) do
            self.table_name = 'fidget_details'
            belongs_to :fidget
          end
        end

        let(:fidget_class) do
          Class.new(ActiveRecord::Base) do
            self.table_name = 'fidgets'
            has_one :fidget_detail
          end
        end

        let(:bulk_id_generator) { proc { SecureRandom.uuid } }

        let(:key_proc) do
          lambda do |klass|
            case klass.to_s
            when 'Fidget'
              %w(id)
            when 'FidgetDetail'
              %w(title)
            else
              raise "Key Columns for #{klass} not defined"
            end

          end
        end

        before(:each) do
          stub_const('Fidget', fidget_class)
          stub_const('FidgetDetail', fidget_detail_class)
          Fidget.reset_column_information
        end


        let(:batch) do
          Deimos::ActiveRecordConsume::BatchRecordList.new(
            [
              Deimos::ActiveRecordConsume::BatchRecord.new(
                klass: Fidget,
                attributes: { test_id: 'id1', some_int: 5, fidget_detail: { title: 'Title 1' } },
                bulk_import_column: 'bulk_import_id',
                bulk_import_id_generator: bulk_id_generator
              ),
              Deimos::ActiveRecordConsume::BatchRecord.new(
                klass: Fidget,
                attributes: { test_id: 'id2', some_int: 10, fidget_detail: { title: 'Title 2' } },
                bulk_import_column: 'bulk_import_id',
                bulk_import_id_generator: bulk_id_generator
              )
            ]
          )
        end

        it 'should not backfill the primary key when the primary_key exists' do
          allow(Fidget).to receive(:where).and_call_original
          results = described_class.new(Widget,
                                        bulk_import_id_generator: bulk_id_generator,
                                        bulk_import_id_column: 'bulk_import_id',
                                        key_col_proc: key_proc).mass_update(batch)
          expect(results.count).to eq(2)
          expect(Fidget.count).to eq(2)
          expect(Fidget).to have_received(:where).with(:bulk_import_id => [instance_of(String), instance_of(String)])
          expect(batch.records.map(&:id)).to eq([1,2])
        end

      end

    end
end
