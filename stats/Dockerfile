FROM docker:stable

COPY ./crontabs/root /etc/crontabs/root
COPY ./bin/stats.sh /stats.sh

RUN chmod +x /stats.sh

CMD ["crond", "-f", "-l", "2"]