[![Build Status](https://travis-ci.org/socrata-platform/docker-registry-sync.svg)](https://travis-ci.org/socrata-platform/docker-registry-sync)
[![Gem Version](https://badge.fury.io/rb/docker-registry-sync.svg)](https://badge.fury.io/rb/docker-registry-sync)

# Docker Registry Sync

When deploying dockerized applications to multiple geographic regions backed by a private docker registry, it advisable to co-locate
docker registries with infrastructure required to access them.  Doing this can cause complications with respect to keeping multiple docker
registries in sync, which is the job of `docker-registry-sync`

Given a docker registry backed by S3, a tagged docker image and target buckets backing other docker registry, docker registry sync will
replicate images to one or more regions in AWS. Optionally supporting S3 employing server side encryption (SSE).

Currently only tested with the legacy [docker-registry](https://github.com/docker/docker-registry).

## Usage

`docker-registry-sync [options] <command> [<image>:<tag>]`

### Commands

| Command | Description |
|---------|-------------|
| sync | Sync docker image from one source registry S3 bucket to one or more S3 buckets. |
| queue-sync | Queue docker image sync job from one source registry S3 bucket to one or more S3 buckets. |
| run-sync | Run queued sysnc jobs |

### Options

| required                 | short flag     | long flag                  | Description |
|--------------------------|----------------|----------------------------|-------------|
| Yes                      | `-s SOURCE`    | `--source-bucket SOURCE`   |   Primary docker registry S3 bucket. Pass as <region>:<bucket> |
| Yes                      | `-t TARGETS`   | `--target-buckets TARGETS` |   S3 buckets to sync to, comma separated. Pass as <region>:<bucket>[,<region>:<bucket>] |
| for run-sync, queue-sync | `-q SQS_QUEUE` | `--queue SQS_QUEUE`        |   SQS queue url used to enqueue sync job. Pass as <region>:<uri> (do not include schema) |
| No                       | `-p PROXY`     | `--proxy PROXY`            |   HTTP proxy URL |
| No                       |                | `--sse`                    |   Copy S3 objects using SSE on the destination using (AES256 only) |
| No                       |                | `--source-sse`             |   Copy S3 objects when the source is using SSE (AES256 only) |
| No                       | `-n POOL`      | `--pool POOL`              |   Size of worker thread pool, defaults to 5. |
| No                       |                | `--unset-proxy`            |  Use if 'http_proxy' is set in your environment, but you don't want to use it... |
