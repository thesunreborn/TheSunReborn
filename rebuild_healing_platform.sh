#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== TheSunReborn Healing Platform - Complete Linux Rebuild ===${NC}"
echo -e "${BLUE}This will rebuild your entire platform from scratch${NC}"

# Configuration
PLATFORM_DIR="$HOME/healing-platform"
SERVICES_DIR="$PLATFORM_DIR/services"
FRONTEND_DIR="$PLATFORM_DIR/frontend"
MOBILE_DIR="$PLATFORM_DIR/mobile"
SCRIPTS_DIR="$PLATFORM_DIR/scripts"

# Clean existing installation
echo -e "${YELLOW}Step 1: Cleaning existing installation...${NC}"
cd "$HOME"
if [ -d "$PLATFORM_DIR" ]; then
    echo "Stopping existing services..."
    cd "$PLATFORM_DIR" && docker-compose down 2>/dev/null || true
    cd "$HOME"
    echo "Removing existing platform directory..."
    rm -rf "$PLATFORM_DIR"
fi

# Update Node.js to latest LTS
echo -e "${YELLOW}Step 2: Updating Node.js to latest LTS...${NC}"
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt update
sudo apt install -y nodejs

echo "Node.js version: $(node -v)"
echo "NPM version: $(npm -v)"

# Create directory structure
echo -e "${YELLOW}Step 3: Creating directory structure...${NC}"
mkdir -p "$PLATFORM_DIR"
mkdir -p "$SERVICES_DIR"
mkdir -p "$FRONTEND_DIR"
mkdir -p "$MOBILE_DIR"
mkdir -p "$SCRIPTS_DIR"
mkdir -p "$PLATFORM_DIR/infra"
mkdir -p "$PLATFORM_DIR/docs"

# Create Docker Compose file
echo -e "${YELLOW}Step 4: Setting up databases...${NC}"
cat > "$PLATFORM_DIR/docker-compose.yml" << 'YAML'
version: '3.3'
services:
  mongodb:
    image: mongo:7.0
    container_name: healing-mongodb
    restart: unless-stopped
    ports:
      - "27017:27017"
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: healing2025
    volumes:
      - mongodb_data:/data/db

  postgres:
    image: timescale/timescaledb:2.11.0-pg15
    container_name: healing-postgres
    restart: unless-stopped
    ports:
      - "5432:5432"
    environment:
      POSTGRES_DB: healing_platform
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: healing2025
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7.2-alpine
    container_name: healing-redis
    restart: unless-stopped
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes --requirepass healing2025
    volumes:
      - redis_data:/data

  mongo-express:
    image: mongo-express:latest
    container_name: healing-mongo-express
    restart: unless-stopped
    ports:
      - "8081:8081"
    environment:
      ME_CONFIG_MONGODB_ADMINUSERNAME: admin
      ME_CONFIG_MONGODB_ADMINPASSWORD: healing2025
      ME_CONFIG_MONGODB_URL: mongodb://admin:healing2025@mongodb:27017/
    depends_on:
      - mongodb

volumes:
  mongodb_data:
  postgres_data:
  redis_data:
YAML

# Create Auth Service (Node.js/Express)
echo -e "${YELLOW}Step 5: Creating Auth Service...${NC}"
mkdir -p "$SERVICES_DIR/auth-service"
cd "$SERVICES_DIR/auth-service"

# Initialize Node.js project
npm init -y
npm install express cors helmet mongoose jsonwebtoken bcryptjs dotenv

# Create auth service files
cat > "server.js" << 'JS'
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const mongoose = require('mongoose');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());

// MongoDB connection
mongoose.connect('mongodb://admin:healing2025@localhost:27017/auth?authSource=admin')
  .then(() => console.log('Connected to MongoDB'))
  .catch(err => console.error('MongoDB connection error:', err));

// Routes
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'auth-service', timestamp: new Date().toISOString() });
});

app.get('/auth', (req, res) => {
  res.json({ message: 'TheSunReborn Auth Service', version: '1.0.0' });
});

app.post('/auth/register', (req, res) => {
  // Registration logic here
  res.json({ message: 'User registration endpoint', data: req.body });
});

app.post('/auth/login', (req, res) => {
  // Login logic here
  res.json({ message: 'User login endpoint', data: req.body });
});

app.listen(PORT, () => {
  console.log(`Auth service running on port ${PORT}`);
});
JS

# Update package.json scripts
node -e "
const pkg = require('./package.json');
pkg.scripts = {
  ...pkg.scripts,
  'start': 'node server.js',
  'dev': 'nodemon server.js'
};
pkg.name = 'thesunreborn-auth-service';
pkg.description = 'Authentication service for TheSunReborn healing platform';
require('fs').writeFileSync('./package.json', JSON.stringify(pkg, null, 2));
"

# Create Protocol Service (Python/FastAPI)
echo -e "${YELLOW}Step 6: Creating Protocol Service...${NC}"
mkdir -p "$SERVICES_DIR/protocol-service"
cd "$SERVICES_DIR/protocol-service"

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install fastapi uvicorn sqlalchemy psycopg2-binary pydantic python-multipart

# Create FastAPI service
cat > "main.py" << 'PY'
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
import uvicorn

app = FastAPI(title="TheSunReborn Protocol Service", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Models
class Protocol(BaseModel):
    id: Optional[int] = None
    name: str
    description: str
    frequency: float
    duration: int
    category: str

class HealthResponse(BaseModel):
    status: str
    service: str
    timestamp: str

# In-memory storage (replace with database)
protocols_db = []

@app.get("/health", response_model=HealthResponse)
async def health_check():
    from datetime import datetime
    return HealthResponse(
        status="healthy",
        service="protocol-service",
        timestamp=datetime.now().isoformat()
    )

@app.get("/protocols", response_model=List[Protocol])
async def get_protocols():
    return protocols_db

@app.post("/protocols", response_model=Protocol)
async def create_protocol(protocol: Protocol):
    protocol.id = len(protocols_db) + 1
    protocols_db.append(protocol)
    return protocol

@app.get("/protocols/{protocol_id}", response_model=Protocol)
async def get_protocol(protocol_id: int):
    for protocol in protocols_db:
        if protocol.id == protocol_id:
            return protocol
    raise HTTPException(status_code=404, detail="Protocol not found")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
PY

cat > "requirements.txt" << 'TXT'
fastapi==0.104.1
uvicorn[standard]==0.24.0
sqlalchemy==2.0.23
psycopg2-binary==2.9.9
pydantic==2.5.0
python-multipart==0.0.6
TXT

# Create Session Service (Node.js/Express)
echo -e "${YELLOW}Step 7: Creating Session Service...${NC}"
mkdir -p "$SERVICES_DIR/session-service"
cd "$SERVICES_DIR/session-service"

npm init -y
npm install express cors helmet redis dotenv socket.io

cat > "server.js" << 'JS'
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const http = require('http');
const socketIo = require('socket.io');
require('dotenv').config();

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

const PORT = process.env.PORT || 3001;

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());

// Routes
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'session-service', timestamp: new Date().toISOString() });
});

app.get('/sessions', (req, res) => {
  res.json({ message: 'TheSunReborn Session Service', version: '1.0.0' });
});

// Socket.IO for real-time session management
io.on('connection', (socket) => {
  console.log('Client connected:', socket.id);

  socket.on('join-session', (sessionId) => {
    socket.join(sessionId);
    console.log(`Client ${socket.id} joined session ${sessionId}`);
  });

  socket.on('session-data', (data) => {
    socket.to(data.sessionId).emit('session-update', data);
  });

  socket.on('disconnect', () => {
    console.log('Client disconnected:', socket.id);
  });
});

server.listen(PORT, () => {
  console.log(`Session service running on port ${PORT}`);
});
JS

# Update package.json
node -e "
const pkg = require('./package.json');
pkg.scripts = {
  ...pkg.scripts,
  'start': 'node server.js',
  'dev': 'nodemon server.js'
};
pkg.name = 'thesunreborn-session-service';
pkg.description = 'Session orchestration service for TheSunReborn healing platform';
require('fs').writeFileSync('./package.json', JSON.stringify(pkg, null, 2));
"

# Create React Frontend
echo -e "${YELLOW}Step 8: Creating React Frontend...${NC}"
cd "$FRONTEND_DIR"
npx create-react-app web-app --template typescript
cd web-app

# Install additional dependencies
npm install @mui/material @emotion/react @emotion/styled @mui/icons-material axios

# Create a basic healing dashboard
cat > "src/App.tsx" << 'TSX'
import React, { useState, useEffect } from 'react';
import {
  AppBar,
  Box,
  Card,
  CardContent,
  Container,
  Grid,
  Toolbar,
  Typography,
  Button,
  Alert
} from '@mui/material';
import { Healing, Psychology, Sensors } from '@mui/icons-material';
import axios from 'axios';

interface ServiceHealth {
  status: string;
  service: string;
  timestamp: string;
}

function App() {
  const [services, setServices] = useState<{[key: string]: ServiceHealth}>({});
  const [loading, setLoading] = useState(true);

  const checkServices = async () => {
    const serviceUrls = {
      'Auth Service': 'http://localhost:3000/health',
      'Protocol Service': 'http://localhost:8000/health',
      'Session Service': 'http://localhost:3001/health'
    };

    const newServices: {[key: string]: ServiceHealth} = {};

    for (const [name, url] of Object.entries(serviceUrls)) {
      try {
        const response = await axios.get(url, { timeout: 5000 });
        newServices[name] = response.data;
      } catch (error) {
        newServices[name] = {
          status: 'error',
          service: name.toLowerCase().replace(' ', '-'),
          timestamp: new Date().toISOString()
        };
      }
    }

    setServices(newServices);
    setLoading(false);
  };

  useEffect(() => {
    checkServices();
    const interval = setInterval(checkServices, 30000); // Check every 30 seconds
    return () => clearInterval(interval);
  }, []);

  return (
    <Box sx={{ flexGrow: 1 }}>
      <AppBar position="static" sx={{ background: 'linear-gradient(45deg, #FE6B8B 30%, #FF8E53 90%)' }}>
        <Toolbar>
          <Healing sx={{ mr: 2 }} />
          <Typography variant="h6" component="div" sx={{ flexGrow: 1 }}>
            TheSunReborn Healing Platform
          </Typography>
        </Toolbar>
      </AppBar>

      <Container maxWidth="lg" sx={{ mt: 4, mb: 4 }}>
        <Grid container spacing={3}>
          <Grid item xs={12}>
            <Typography variant="h4" component="h1" gutterBottom align="center">
              Healing Platform Dashboard
            </Typography>
          </Grid>

          {/* Service Status Cards */}
          {Object.entries(services).map(([name, service]) => (
            <Grid item xs={12} md={4} key={name}>
              <Card>
                <CardContent>
                  <Box sx={{ display: 'flex', alignItems: 'center', mb: 1 }}>
                    {name.includes('Auth') && <Psychology sx={{ mr: 1 }} />}
                    {name.includes('Protocol') && <Sensors sx={{ mr: 1 }} />}
                    {name.includes('Session') && <Healing sx={{ mr: 1 }} />}
                    <Typography variant="h6">{name}</Typography>
                  </Box>
                  <Alert 
                    severity={service.status === 'healthy' ? 'success' : 'error'}
                    sx={{ mb: 1 }}
                  >
                    Status: {service.status}
                  </Alert>
                  <Typography variant="body2" color="textSecondary">
                    Last check: {new Date(service.timestamp).toLocaleString()}
                  </Typography>
                </CardContent>
              </Card>
            </Grid>
          ))}

          <Grid item xs={12}>
            <Card>
              <CardContent>
                <Typography variant="h5" gutterBottom>
                  Quick Actions
                </Typography>
                <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap' }}>
                  <Button variant="contained" color="primary">
                    Start Healing Session
                  </Button>
                  <Button variant="outlined" color="secondary">
                    View Protocols
                  </Button>
                  <Button variant="outlined" onClick={checkServices}>
                    Refresh Status
                  </Button>
                </Box>
              </CardContent>
            </Card>
          </Grid>
        </Grid>
      </Container>
    </Box>
  );
}

export default App;
TSX

# Create launch scripts
echo -e "${YELLOW}Step 9: Creating launch scripts...${NC}"
cd "$SCRIPTS_DIR"

# Main launcher script
cat > "launch_platform.sh" << 'LAUNCHER'
#!/bin/bash
set -e

PLATFORM_DIR="$HOME/healing-platform"
cd "$PLATFORM_DIR"

echo "=== TheSunReborn Healing Platform Launcher ==="
echo

# Start databases
echo "1. Starting databases..."
docker-compose up -d
sleep 10

echo "2. Starting backend services..."

# Start Auth Service
cd "$PLATFORM_DIR/services/auth-service"
echo "Starting Auth Service on port 3000..."
nohup npm start > ../../../logs/auth-service.log 2>&1 &
echo $! > ../../../logs/auth-service.pid

# Start Protocol Service
cd "$PLATFORM_DIR/services/protocol-service"
echo "Starting Protocol Service on port 8000..."
source venv/bin/activate
nohup uvicorn main:app --host 0.0.0.0 --port 8000 > ../../../logs/protocol-service.log 2>&1 &
echo $! > ../../../logs/protocol-service.pid

# Start Session Service
cd "$PLATFORM_DIR/services/session-service"
echo "Starting Session Service on port 3001..."
nohup npm start > ../../../logs/session-service.log 2>&1 &
echo $! > ../../../logs/session-service.pid

# Start Frontend
cd "$PLATFORM_DIR/frontend/web-app"
echo "Starting Web Dashboard on port 3000..."
nohup npm start > ../../../logs/web-app.log 2>&1 &
echo $! > ../../../logs/web-app.pid

echo
echo "=== Platform Started! ==="
echo "Web Dashboard: http://localhost:3000"
echo "Auth API: http://localhost:3000/auth"
echo "Protocol API: http://localhost:8000/protocols"
echo "Session API: http://localhost:3001/sessions"
echo "Mongo Express: http://localhost:8081"
echo
echo "Log files are in $PLATFORM_DIR/logs/"
echo "To stop all services, run: ./stop_platform.sh"
LAUNCHER

# Stop script
cat > "stop_platform.sh" << 'STOPPER'
#!/bin/bash

PLATFORM_DIR="$HOME/healing-platform"
cd "$PLATFORM_DIR"

echo "Stopping TheSunReborn Healing Platform..."

# Stop Node processes
for pidfile in logs/*.pid; do
  if [ -f "$pidfile" ]; then
    pid=$(cat "$pidfile")
    if kill -0 "$pid" 2>/dev/null; then
      echo "Stopping process $pid"
      kill "$pid"
    fi
    rm "$pidfile"
  fi
done

# Stop Docker containers
docker-compose down

echo "Platform stopped."
STOPPER

# Status check script
cat > "status.sh" << 'STATUS'
#!/bin/bash

echo "=== TheSunReborn Platform Status ==="
echo

# Check Docker containers
echo "Database Services:"
docker-compose ps

echo
echo "Backend Services:"
curl -s http://localhost:3000/health 2>/dev/null && echo "✓ Auth Service: Online" || echo "✗ Auth Service: Offline"
curl -s http://localhost:8000/health 2>/dev/null && echo "✓ Protocol Service: Online" || echo "✗ Protocol Service: Offline"  
curl -s http://localhost:3001/health 2>/dev/null && echo "✓ Session Service: Online" || echo "✗ Session Service: Offline"

echo
echo "Frontend:"
curl -s http://localhost:3000 2>/dev/null >/dev/null && echo "✓ Web Dashboard: Online" || echo "✗ Web Dashboard: Offline"

echo
echo "Access URLs:"
echo "- Web Dashboard: http://localhost:3000"
echo "- Auth API: http://localhost:3000/auth"  
echo "- Protocol API: http://localhost:8000/protocols"
echo "- Session API: http://localhost:3001/sessions"
echo "- Mongo Express: http://localhost:8081"
STATUS

# Make scripts executable
chmod +x *.sh

# Create log directory
mkdir -p "$PLATFORM_DIR/logs"

# Create main README
echo -e "${YELLOW}Step 10: Creating documentation...${NC}"
cat > "$PLATFORM_DIR/README.md" << 'README'
# TheSunReborn Healing Platform

A complete healing platform with microservices architecture, real-time session management, and modern web dashboard.

## Quick Start

1. **Start the platform:**
   ```bash
   cd ~/healing-platform/scripts
   ./launch_platform.sh
   ```

2. **Check status:**
   ```bash
   ./status.sh
   ```

3. **Stop the platform:**
   ```bash
   ./stop_platform.sh
   ```

## Access Points

- **Web Dashboard:** http://localhost:3000
- **Auth API:** http://localhost:3000/auth
- **Protocol API:** http://localhost:8000/protocols  
- **Session API:** http://localhost:3001/sessions
- **Database Admin:** http://localhost:8081

## Architecture

```
├── services/
│   ├── auth-service/          # Node.js authentication
│   ├── protocol-service/      # Python FastAPI protocols
│   └── session-service/       # Node.js real-time sessions
├── frontend/
│   └── web-app/              # React TypeScript dashboard
├── scripts/                  # Platform management scripts
└── docker-compose.yml       # Database containers
```

## Development

Each service can be run individually:

```bash
# Auth service
cd services/auth-service && npm run dev

# Protocol service  
cd services/protocol-service && source venv/bin/activate && uvicorn main:app --reload

# Session service
cd services/session-service && npm run dev

# Frontend
cd frontend/web-app && npm start
```

## Logs

Service logs are available in `logs/`:
- `auth-service.log`
- `protocol-service.log` 
- `session-service.log`
- `web-app.log`
README

# Start the platform
echo -e "${YELLOW}Step 11: Starting the platform...${NC}"
cd "$PLATFORM_DIR"

# Start databases first
echo "Starting databases..."
docker-compose up -d
sleep 5

echo -e "${GREEN}=== Platform Rebuilt Successfully! ===${NC}"
echo
echo -e "${BLUE}Next steps:${NC}"
echo "1. cd ~/healing-platform/scripts"
echo "2. ./launch_platform.sh"
echo "3. Open http://localhost:3000 in your browser"
echo
echo -e "${BLUE}Management commands:${NC}"
echo "- Start: ./scripts/launch_platform.sh"  
echo "- Stop: ./scripts/stop_platform.sh"
echo "- Status: ./scripts/status.sh"
echo
echo -e "${YELLOW}The platform is ready for development and testing!${NC}"
