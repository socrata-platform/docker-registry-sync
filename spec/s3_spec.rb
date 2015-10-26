require 'json'
require 'spec_helper'
require 'docker/registry/sync'
require 'aws-sdk'

def stub_s3_response(action, resp)
  Aws.config[:s3] = { stub_responses: {} }
  Aws.config[:s3][:stub_responses][action] = resp
end

describe 'Docker::Register::Sync::CMD' '#sync_tag' do
  before do
    Docker::Registry::Sync::CMD.configure(
      'us-west-2:test-source-bucket',
      'us-west-2:test-target-bucket',
      'us-west-2:test-sqs-queue',
      false,
      false,
      2,
      :off
    )
    Docker::Registry::Sync::CMD.configure_workers
  end

  context 'syncing tags' do
    it 'successfully syncs' do
      img_id = 'sync-successful'
      stub_s3_response(:get_object, { body: img_id })
      allow(Docker::Registry::Sync::CMD).to receive(:sync_image).with(
        img_id,
        'test-target-bucket',
        'us-west-2',
        false,
        'test-source-bucket',
        'us-west-2'
      )
      allow(Docker::Registry::Sync::CMD).to receive(:sync_keys)
      res = Docker::Registry::Sync::CMD.sync_tag('sync-image', 'sync-tag', 'test-target-bucket', 'us-west-2', false)
      expect(res).to be true
    end

    it 'S3 API failure' do
      img_id = 'sync-unsuccessful'
      stub_s3_response(:get_object, RuntimeError.new('api failure'))
      allow(Docker::Registry::Sync::CMD).to receive(:sync_keys)
      res = Docker::Registry::Sync::CMD.sync_tag('sync-image', 'sync-tag', 'test-target-bucket', 'us-west-2', false)
      expect(res).to be false
    end
  end
end

describe 'Docker::Register::Sync::CMD' '#sync_repo' do
  before do
    Docker::Registry::Sync::CMD.configure(
      'us-west-2:test-source-bucket',
      'us-west-2:test-target-bucket',
      'us-west-2:test-sqs-queue',
      false,
      false,
      2,
      :off
    )
    Docker::Registry::Sync::CMD.configure_workers
  end

  context 'syncing repositories' do
    it 'successfully syncs' do
      images = [{'id' => 'image-one'}, {'id' => 'image-two'}]
      allow(Docker::Registry::Sync::CMD).to receive(:sync_prefix)
      images.each do |i|
        allow(Docker::Registry::Sync::CMD).to receive(:sync_image).with(i['id'],'test-target-bucket', 'us-west-2', false, 'test-source-bucket', 'us-west-2')
      end

      stub_s3_response(:get_object, { body: JSON.dump(images)})
      res = Docker::Registry::Sync::CMD.sync_repo('sync-repo', 'test-target-bucket', 'us-west-2', false)
      expect(res).to be true
    end

    it 'S3 API failure' do
      images = [{'id' => 'image-one'}, {'id' => 'image-two'}]
      allow(Docker::Registry::Sync::CMD).to receive(:sync_prefix)
      images.each do |i|
        allow(Docker::Registry::Sync::CMD).to receive(:sync_image).with(i['id'],'test-target-bucket', 'us-west-2', false, 'test-source-bucket', 'us-west-2')
      end

      stub_s3_response(:get_object, RuntimeError.new('api failure'))
      res = Docker::Registry::Sync::CMD.sync_repo('sync-repo', 'test-target-bucket', 'us-west-2', false)
      expect(res).to be false
    end
  end
end

describe 'Docker::Register::Sync::CMD' '#sync_key_consumer' do
  before do
    Docker::Registry::Sync::CMD.configure(
      'us-west-2:test-source-bucket',
      'us-west-2:test-target-bucket',
      'us-west-2:test-sqs-queue',
      false,
      false,
      1,
      :off
    )
    Docker::Registry::Sync::CMD.configure_workers
  end

  context 'runs' do
    it 'successfully exits with no work and producer is finished' do
      t = Thread.new do
        Docker::Registry::Sync::CMD.sync_key_consumer
      end
      Docker::Registry::Sync::CMD.producer_finished = true
      t.join
      expect(Docker::Registry::Sync::CMD.work_queue.length).to be 0
      expect(t.status).to be false
    end

    it 'successfully exits when a child encounters an exception' do
      Docker::Registry::Sync::CMD.work_queue << {
        region: 'us-west-2',
        key: 'exception-raiser',
        bucket: 'exception-raiser',
        copy_source: 'exception-raiser',
      }
      Docker::Registry::Sync::CMD.work_queue << {
        region: 'us-west-2',
        key: 'exception-raiser',
        bucket: 'exception-raiser',
        copy_source: 'exception-raiser',
      }
      Docker::Registry::Sync::CMD.producer_finished = true
      stub_s3_response(:copy_object, RuntimeError.new('api failure'))
      t = Thread.new do
        Docker::Registry::Sync::CMD.sync_key_consumer
      end

      t.join
      Docker::Registry::Sync::CMD.threads.each { |t| t.join }
      expect(t.status).to be false
      expect(Docker::Registry::Sync::CMD.threads[0].status).to be false

      expect(Docker::Registry::Sync::CMD.work_queue.length).to be 0
      expect(Docker::Registry::Sync::CMD.status_queue.length).to be 2
      expect(Docker::Registry::Sync::CMD.status_queue.pop).to be false
      expect(Docker::Registry::Sync::CMD.status_queue.pop).to be false
    end
  end
end
