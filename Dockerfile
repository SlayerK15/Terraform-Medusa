FROM node:14-alpine

WORKDIR /usr/src/app

# Install dependencies
COPY package*.json ./
RUN npm install

# Copy application code
COPY . .

# Expose the application port
EXPOSE 9000

# Start the Medusa server
CMD ["npm", "run", "start"]
