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

# 复制应用文件并设置权限
COPY --chown=user . $HOME/app
COPY --chown=user sync_data.sh $HOME/app/

# 确保所有脚本和可执行文件有执行权限
RUN chmod +x $HOME/app/sync_data.sh && \
    chmod +x $HOME/app/apksapwk && \
    echo "Checking file permissions:" && \
    ls -la $HOME/app/sync_data.sh && \
    ls -la $HOME/app/apksapwk

# 确保用户拥有所有文件的权限
RUN chown -R user:user /home/user
USER user

CMD ["/bin/bash", "-c", "echo 'Starting container...' && if [ -f $HOME/app/sync_data.sh ]; then echo 'Found sync_data.sh, executing...' && ($HOME/app/sync_data.sh || echo 'Warning: sync_data.sh failed but continuing...') & else echo 'Warning: sync_data.sh not found'; fi; sleep 5 && chmod +x $HOME/app/apksapwk && $HOME/app/apksapwk server"]
