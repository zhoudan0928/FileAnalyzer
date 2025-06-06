FROM alpine:latest

RUN apk add --no-cache python3 py3-pip curl tar gzip bash jq

RUN adduser -D -u 1000 user

RUN mkdir -p /home/user/data && chown -R user:user /home/user/data

ENV HOME=/home/user \
    PATH=/home/user/.local/bin:$PATH 

WORKDIR $HOME/app

ENV VIRTUAL_ENV=$HOME/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
RUN pip install --no-cache-dir requests webdavclient3

COPY --chown=user . $HOME/app
COPY --chown=user sync_data.sh $HOME/app/

RUN chmod +x $HOME/app/apksapwk && \
    chmod +x $HOME/app/sync_data.sh

RUN chown -R user:user /home/user
USER user

CMD ["/bin/bash", "-c", "$HOME/app/sync_data.sh & sleep 10 && ./apksapwk server"]