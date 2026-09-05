FROM node:22-alpine
WORKDIR /app
COPY server.mjs ./server.mjs
RUN mkdir /data && chown node:node /data
USER node
ENV HOST=0.0.0.0 PORT=8787 FERNDROP_DATA=/data
EXPOSE 8787
CMD ["node", "server.mjs"]
