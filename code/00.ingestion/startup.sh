#!/bin/sh
# https://devopsheaven.com/cron/docker/alpine/linux/2017/10/30/run-cron-docker-alpine.html
# NOTE: this file is not used, keeping for now but could be deleted later as cleanup
echo "Starting startup.sh.."
#echo "*       *       *       *       *       run-parts /etc/periodic/1min" >> /etc/crontabs/root
crontab -l
