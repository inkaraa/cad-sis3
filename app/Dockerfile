FROM node:24-slim
WORKDIR /app
ENV NODE_ENV=production
COPY package.json ./
RUN npm install --omit=dev
COPY server.js ./
USER node
EXPOSE 8080
CMD ["node", "server.js"]
