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
              s3.head_object(bucket: bucket, key: "registry/repositories/#{image}/_index_images")
            rescue Aws::S3::Errors::NotFound
              false
            else
              true
            end
          end


          def sync_tag(image, tag, bucket, region, sse, source_bucket = nil, source_region = nil)
            source_region ||= @config.source_region
            source_bucket ||= @config.source_bucket

            s3_source = Aws::S3::Client.new(region: source_region)
            s3_target = Aws::S3::Client.new(region: region)

            begin
              keys = ["tag#{tag}_json", "tag_#{tag}", '_index_images'].map do |key|
                "registry/repositories/#{image}/#{key}"
              end
              sync_keys(s3_target, bucket, sse, keys, source_bucket)

              img_id = s3_source.get_object(bucket: source_bucket, key: "registry/repositories/#{image}/tag_#{tag}").body.read
              sync_image(img_id, bucket, region, sse, source_bucket, source_region)
            rescue Exception => e
              @config.logger.error "An unexpected error occoured while syncing tag #{image}:#{tag}: #{e}"
              false
            else
              true
            end
          end

          def sync_repo(repo, bucket, region, sse, source_bucket = nil, source_region = nil)
            source_region ||= @config.source_region
            source_bucket ||= @config.source_bucket
            s3_source = Aws::S3::Client.new(region: source_region)
            s3_target = Aws::S3::Client.new(region: region)

            begin
              rep_prefix = "registry/repositories/#{repo}/"
              sync_prefix(s3_source, s3_target, bucket, sse, rep_prefix, source_bucket)

              img_index_resp = s3_source.get_object(bucket: source_bucket, key: "registry/repositories/#{repo}/_index_images")
              JSON.load(img_index_resp.body.read).each do |image|
                sync_image(image['id'], bucket, region, sse, source_bucket, source_region)
              end
            rescue Exception => e
              @config.logger.error "An unexpected error occoured while syncing repo #{repo}: #{e}"
              false
            else
              true
            end
          end

          def sync_image(image_id, bucket, region, sse, source_bucket = nil, source_region = nil)
            source_region ||= @config.source_region
            source_bucket ||= @config.source_bucket
            s3_source = Aws::S3::Client.new(region: source_region)
            s3_target = Aws::S3::Client.new(region: region)

            ancestry_resp = s3_source.get_object(bucket: source_bucket, key: "registry/images/#{image_id}/ancestry")
            # Ancestry includes self
            JSON.load(ancestry_resp.body.read).each do |image|
              sync_prefix(s3_source, s3_target, bucket, sse, "registry/images/#{image}/", source_bucket)
            end
          end

          @private
          def sync_prefix(source_client, target_client, target_bucket, target_sse, prefix, source_bucket)
            keys = []
            img_resp = source_client.list_objects(bucket: source_bucket, prefix: prefix)

            loop do
              img_resp.contents.each do |item|
                keys << item.key
              end
              if img_resp.last_page?
                break
              else
                img_resp.next_page
              end
            end
            sync_keys(target_client, target_bucket, target_sse, keys, source_bucket)
          end

          def sync_keys(target_client, target_bucket, target_sse, keys, source_bucket)
            keys.each do |key|
              @config.logger.info "Syncing key #{source_bucket}/#{key} to bucket #{target_bucket}"
              opts = {acl: 'bucket-owner-full-control',
                      bucket: target_bucket,
                      key: key,
                      copy_source: "#{source_bucket}/#{key}"}
              if @config.sse || target_sse
                opts[:server_side_encryption] = 'AES256'
              end
              if @config.source_sse
                opts[:copy_source_sse_customer_algorithm] = 'AES256'
              end
              target_client.copy_object(opts)
            end
          end
        end
      end
    end
  end
end
