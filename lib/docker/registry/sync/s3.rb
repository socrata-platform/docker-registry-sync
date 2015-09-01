require 'aws-sdk'

module Docker
  module Registry
    module Sync
      module CMD
        include Docker::Registry::Sync

        class << self
          def image_exists?(image, bucket, region)
            s3 = Aws::S3::Client.new(region: region)
            begin
              s3.head_object({bucket: bucket, key: "registry/repositories/#{image}/_index_images"})
            rescue Aws::S3::Errors::NotFound
              false
            else
              true
            end
          end

          def sync_prefix(source_client, target_client, target_bucket, prefix, source_bucket = nil)
            source_bucket ||= @config.source_bucket
            keys = []
            img_resp = source_client.list_objects(bucket: source_bucket, prefix: prefix)

            while true
              img_resp.contents.each do |item|
                keys << item.key
              end
              if img_resp.last_page?
                break
              else
                img_resp.next_page
              end
            end
            sync_keys(target_client, target_bucket, keys)
          end

          def sync_keys(target_client, target_bucket, keys, source_bucket = nil)
            source_bucket ||= @config.source_bucket
            keys.each do |key|
              @config.logger.info "Syncing key #{source_bucket}/#{key} to bucket #{target_bucket}"
              target_client.copy_object({
                acl: 'bucket-owner-full-control',
                bucket: target_bucket,
                key: key,
                copy_source: "#{source_bucket}/#{key}"
              })
            end
          end

          def sync_tag(image, tag, bucket, region, source_bucket = nil, source_region = nil)
            source_region ||= @config.source_region
            source_bucket ||= @config.source_bucket

            s3_source = Aws::S3::Client.new(region: source_region)
            s3_target = Aws::S3::Client.new(region: region)

            begin
              keys = ["tag#{tag}_json", "tag_#{tag}", "_index_images"].map do |key|
                "registry/repositories/#{image}/#{key}"
              end
              sync_keys(s3_target, bucket, keys)

              img_id_resp = s3_source.get_object(bucket: source_bucket, key: "registry/repositories/#{image}/tag_#{tag}")
              img_prefix = "registry/images/#{img_id_resp.body.read}/"
              sync_prefix(s3_source, s3_target, bucket, img_prefix)
            rescue Exception => e
              @config.logger.error "An unexpected error occoured while syncing tag #{image}:#{tag}: #{e}"
              false
            else
              true
            end
          end

          def sync_image(image, bucket, region, source_bucket = nil, source_region = nil)
            source_region ||= @config.source_region
            source_bucket ||= @config.source_bucket
            s3_source = Aws::S3::Client.new(region: source_region)
            s3_target = Aws::S3::Client.new(region: region)

            begin
              rep_prefix = "registry/repositories/#{image}/"
              sync_prefix(s3_source, s3_target, bucket, rep_prefix)

              img_index_resp = s3_source.get_object(bucket: source_bucket, key: "registry/repositories/#{image}/_index_images")
              JSON.load(img_index_resp.body.read).each do |image|
                image_prefix = "registry/images/#{image['id']}/"
	        sync_prefix(s3_source, s3_target, bucket, image_prefix)
              end
            rescue Exception => e
              @config.logger.error "An unexpected error occoured while syncing image #{image}: #{e}"
              false
            else
              true
            end
          end
        end
      end
    end
  end
end
