# The SpaceNotes Live room server, with the web app it serves.
# Built from the repository root, because the server shares the reducer in
# web/src/core with the web client.
FROM node:22-slim
WORKDIR /app
COPY server/package.json server/
COPY server/src server/src
COPY web/src web/src
COPY web/app web/app
COPY web/vendor web/vendor
ENV NODE_ENV=production
EXPOSE 8080
USER node
WORKDIR /app/server
CMD ["node", "src/server.js"]
