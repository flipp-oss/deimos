# frozen_string_literal: true

RSpec.describe Deimos::ActiveRecordConsume::BatchConsumption do
  let(:batch_consumer) do
    Deimos::ActiveRecordConsumer.new
  end

  describe '#update_database' do
    describe 'upsert_records' do
      let(:records) do
        [
          Deimos::Message.new({ v: 1 }, key: 1),
          Deimos::Message.new({ v: 2 }, key: 2),
          Deimos::Message.new({ v: 3 }, key: 3),
          Deimos::Message.new({ v: 4 }, key: 4),
          Deimos::Message.new({ v: 5 }, key: 5)
        ]
      end

      it 'should be called 1 time when record size < max batch size' do
        batch_consumer.class.config[:max_db_batch_size] = records.size + 1
        expect(batch_consumer).to receive(:upsert_records).once

        batch_consumer.send(:update_database, records)
      end

      it 'should be called 1 time when record size == max batch size' do
        batch_consumer.class.config[:max_db_batch_size] = records.size
        expect(batch_consumer).to receive(:upsert_records).once

        batch_consumer.send(:update_database, records)
      end

      it 'should be called multiple times when record size > max batch size' do
        batch_consumer.class.config[:max_db_batch_size] = records.size - 1
        expect(batch_consumer).to receive(:upsert_records).twice

        batch_consumer.send(:update_database, records)
      end

      it 'should be called records.size times when max batch size is 1' do
        batch_consumer.class.config[:max_db_batch_size] = 1
        expect(batch_consumer).to receive(:upsert_records).exactly(records.size)

        batch_consumer.send(:update_database, records)
      end

      it 'should be called 1 time when batch size is nil' do
        batch_consumer.class.config[:max_db_batch_size] = nil
        expect(batch_consumer).to receive(:upsert_records).once

        batch_consumer.send(:update_database, records)
      end
    end

    describe 'remove_records' do
      let(:records) do
        [
          Deimos::Message.new(nil, key: 1),
          Deimos::Message.new(nil, key: 2),
          Deimos::Message.new(nil, key: 3),
          Deimos::Message.new(nil, key: 4),
          Deimos::Message.new(nil, key: 5)
        ]
      end

      it 'should be called 1 time when record size < max batch size' do
        batch_consumer.class.config[:max_db_batch_size] = records.size + 1
        expect(batch_consumer).to receive(:remove_records).once

        batch_consumer.send(:update_database, records)
      end

      it 'should be called 1 time when record size == max batch size' do
        batch_consumer.class.config[:max_db_batch_size] = records.size
        expect(batch_consumer).to receive(:remove_records).once

        batch_consumer.send(:update_database, records)
      end

      it 'should be called multiple times when record size > max batch size' do
        batch_consumer.class.config[:max_db_batch_size] = records.size - 1
        expect(batch_consumer).to receive(:remove_records).twice

        batch_consumer.send(:update_database, records)
      end

      it 'should be called record.size times when max batch size is 1' do
        batch_consumer.class.config[:max_db_batch_size] = 1
        expect(batch_consumer).to receive(:remove_records).exactly(records.size)

        batch_consumer.send(:update_database, records)
      end

      it 'should be called 1 time when batch size is nil' do
        batch_consumer.class.config[:max_db_batch_size] = nil
        expect(batch_consumer).to receive(:remove_records).once

        batch_consumer.send(:update_database, records)
      end
    end
  end
end
