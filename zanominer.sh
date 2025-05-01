#!/bin/bash

# Zano Miner & Staking Setup Script
# For Ubuntu Desktop with NVIDIA GPU Support
# License: Apache 2.0

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration URLs and filenames
ZANO_PREFIX_URL="https://build.zano.org/builds/"
ZANO_IMAGE_FILENAME="zano-linux-x64-develop-v2.0.1.367[d63feec].AppImage"
ZANO_URL=${ZANO_PREFIX_URL}${ZANO_IMAGE_FILENAME}

# User input variables
REWARD_ADDRESS=""
WALLET_PASSWORD=""
WALLET_NAME=""
SEED_PASSWORD=""
SET_OWN_WALLET_PASSWORD=""
SET_OWN_SEED_PASSWORD=""
USE_SEPARATE_REWARD=""
START_SERVICES_AFTER_INSTALL=""
REWARD_OPTION=""
USE_POOL_MINING=""
POOL_WORKER_NAME=""
CREATE_WALLET_YES=""

# Mining and network configuration
TT_MINER_VERSION="2023.1.0"
STRATUM_PORT="11555"
POS_RPC_PORT="50005"
ZANOD_PID=""
ZANO_DIR="$HOME/zano-project"

# Logging configuration
LOG_DIR="/var/log/zano"
INSTALL_LOG="${LOG_DIR}/install.log"

# Part 2: Core Service Functions

install_dependencies() {
    log "Checking and installing system dependencies..."
    
    sudo apt update

    if lspci | grep -i nvidia > /dev/null; then
        log "NVIDIA GPU detected. Checking NVIDIA drivers..."
        
        if ! nvidia-smi &>/dev/null; then
            log "Installing NVIDIA drivers..."
            sudo ubuntu-drivers autoinstall
        else
            log "NVIDIA drivers are already installed: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader)"
        fi
        
        if ! command -v nvcc &>/dev/null; then
            log "Installing CUDA toolkit..."
            sudo apt install -y nvidia-cuda-toolkit
        else
            log "CUDA toolkit is already installed: $(nvcc --version | head -n1)"
        fi
    else
        warn "No NVIDIA GPU detected. Mining performance may be limited."
    fi

    sudo apt install -y \
        wget \
        curl \
        tar \
        build-essential \
        software-properties-common \
        git \
        nvidia-cuda-toolkit \
        nvidia-driver-535 \
        gpg \
        pwgen \
        jq

    mkdir -p "$LOG_DIR"
    touch "$INSTALL_LOG"
    chmod 644 "$INSTALL_LOG"
}

download_zano_components() {
    log "Starting download of Zano components..."
    
    mkdir -p "$ZANO_DIR"
    cd "$ZANO_DIR" || error "Failed to change to Zano directory"
    
    if [ -f "$ZANO_DIR/simplewallet" ] && [ -f "$ZANO_DIR/zanod" ]; then
        log "Zano components already present, skipping download and extraction..."
        return
    fi

    if [ ! -f ${ZANO_IMAGE_FILENAME} ]; then
        log "Downloading Zano CLI Wallet..."
        wget $ZANO_URL || error "Failed to download Zano CLI Wallet"
    fi
   
    log "Extracting Zano components..."
    chmod +x $ZANO_IMAGE_FILENAME
    ${ZANO_DIR}/$ZANO_IMAGE_FILENAME --appimage-extract || error "Failed to extract AppImage"
    
    mv "$ZANO_DIR/squashfs-root/usr/bin/simplewallet" "$ZANO_DIR/"
    mv "$ZANO_DIR/squashfs-root/usr/bin/zanod" "$ZANO_DIR/"
    rm -r "$ZANO_DIR/squashfs-root"
}

setup_tt_miner() {
    log "Setting up TT-Miner..."
    
    cd "$ZANO_DIR" || error "Failed to change to Zano directory"

    if [ ! -f TT-Miner-${TT_MINER_VERSION}.tar.gz ]; then
        log "Downloading TT-Miner"
        wget https://github.com/TrailingStop/TT-Miner-release/releases/download/${TT_MINER_VERSION}/TT-Miner-${TT_MINER_VERSION}.tar.gz
    fi

    tar -xf TT-Miner-${TT_MINER_VERSION}.tar.gz
    chmod +x TT-Miner
}

create_service_scripts() {
    log "Creating service scripts..."

    if [[ $USE_POOL_MINING =~ ^[Yy]$ ]]; then
        sudo rm /usr/local/bin/run-zanod.sh
        sudo tee /usr/local/bin/run-zanod.sh > /dev/null << EOF
#!/bin/bash
cd ${ZANO_DIR}
./zanod --no-console
EOF
    else
        sudo rm /usr/local/bin/run-zanod.sh
        sudo tee /usr/local/bin/run-zanod.sh > /dev/null << EOF
#!/bin/bash
cd ${ZANO_DIR}
./zanod --stratum --stratum-miner-address=${WALLET_ADDRESS} --stratum-bind-port=${STRATUM_PORT} --no-console
EOF
    fi

    if [[ $USE_POOL_MINING =~ ^[Yy]$ ]]; then
        sudo rm /usr/local/bin/run-tt-miner.sh
        sudo tee /usr/local/bin/run-tt-miner.sh > /dev/null << EOF
#!/bin/bash
cd ${ZANO_DIR}/TT-Miner
./TT-Miner -luck -coin ZANO -P ssl://${WALLET_ADDRESS}.${POOL_WORKER_NAME}@pool.woolypooly.com:3147
EOF
    else
        sudo rm /usr/local/bin/run-tt-miner.sh
        sudo tee /usr/local/bin/run-tt-miner.sh > /dev/null << EOF
#!/bin/bash
cd ${ZANO_DIR}/TT-Miner
./TT-Miner -luck -coin ZANO -u miner -o 127.0.0.1:${STRATUM_PORT}
EOF
    fi

    sudo rm /usr/local/bin/run-pos-mining.sh
    sudo tee /usr/local/bin/run-pos-mining.sh > /dev/null << EOF
#!/bin/bash
cd ${ZANO_DIR}
./simplewallet --wallet-file=${WALLET_NAME}.wallet --password=${WALLET_PASSWORD} --rpc-bind-port=${POS_RPC_PORT} --do-pos-mining --log-level=0 --log-file=pos-mining.log --deaf ${REWARD_OPTION}
EOF

    sudo chmod +x /usr/local/bin/run-zanod.sh
    sudo chmod +x /usr/local/bin/run-tt-miner.sh
    sudo chmod +x /usr/local/bin/run-pos-mining.sh
}

create_systemd_services() {
    log "Creating systemd service files..."

    sudo tee /etc/systemd/system/zanod.service > /dev/null << EOF
[Unit]
Description=Zano Blockchain Daemon
After=network.target

[Service]
Type=simple
User=${USER}
ExecStart=/usr/local/bin/run-zanod.sh
StandardInput=null
StandardOutput=append:/var/log/zanod.log
StandardError=append:/var/log/zanod.error.log
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo tee /etc/systemd/system/tt-miner.service > /dev/null << EOF
[Unit]
Description=TT-Miner for Zano
After=zanod.service
Requires=zanod.service

[Service]
Type=simple
User=${USER}
ExecStart=/usr/local/bin/run-tt-miner.sh
StandardOutput=append:/var/log/tt-miner.log
StandardError=append:/var/log/tt-miner.error.log
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo tee /etc/systemd/system/zano-pos-mining.service > /dev/null << EOF
[Unit]
Description=Zano Proof of Stake Mining
After=zanod.service
Requires=zanod.service

[Service]
Type=simple
User=${USER}
ExecStart=/usr/local/bin/run-pos-mining.sh
StandardOutput=append:/var/log/zano-pos-mining.log
StandardError=append:/var/log/zano-pos-mining.error.log
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    
    if [[ $START_SERVICES_AFTER_INSTALL =~ ^[Yy]$ ]]; then
        sudo systemctl enable zanod.service
        sudo systemctl enable tt-miner.service
        sudo systemctl enable zano-pos-mining.service
    fi
}

# Part 3: Helper/Status Functions

log() {
    echo -e "${GREEN}[ZANO SETUP]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$INSTALL_LOG"
    sleep 1
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$INSTALL_LOG"
    sleep 1
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$INSTALL_LOG"
    sleep 1
    exit 1
}

is_zanod_running() {
    if pgrep -x "zanod" >/dev/null; then
        return 0
    elif systemctl is-active --quiet zanod.service; then
        return 0
    else
        return 1
    fi
}

is_wallet_exists() {
    local wallet_name="$1"
    if [ -f "${ZANO_DIR}/${wallet_name}.wallet" ]; then
        return 0
    else
        return 1
    fi
}

check_sync_status() {
    if ! is_zanod_running; then
        echo -e "${RED}Zano daemon is not running${NC}"
        return 1
    fi

    local status
    status=$(curl -s http://127.0.0.1:12111/getinfo)
    if [ $? -eq 0 ]; then
        local height=$(echo $status | jq -r '.height')
        local incoming_connections=$(echo $status | jq -r '.incoming_connections_count')
        local outgoing_connections=$(echo $status | jq -r '.outgoing_connections_count')
        
        echo -e "${GREEN}Blockchain Height: $height${NC}"
        echo -e "${BLUE}Connections: In: $incoming_connections, Out: $outgoing_connections${NC}"
    else
        echo -e "${RED}Failed to get sync status${NC}"
        return 1
    fi
}

show_mining_status() {
    if ! is_zanod_running; then
        echo -e "${RED}Zano daemon is not running${NC}"
        return 1
    fi

    if pgrep -x "TT-Miner" >/dev/null || systemctl is-active --quiet tt-miner.service; then
        echo -e "${GREEN}Mining is active${NC}"
        if [ -f "/var/log/tt-miner.log" ]; then
            local hashrate=$(tail -n 50 /var/log/tt-miner.log | grep "GPU" | tail -n 1)
            echo -e "${BLUE}Current Hashrate:${NC} $hashrate"
        fi
    else
        echo -e "${RED}Mining is not active${NC}"
    fi
}

show_staking_status() {
    if ! is_zanod_running; then
        echo -e "${RED}Zano daemon is not running${NC}"
        return 1
    fi

    if pgrep -x "simplewallet" >/dev/null || systemctl is-active --quiet zano-pos-mining.service; then
        echo -e "${GREEN}Staking is active${NC}"
        if [ -f "/var/log/zano-pos-mining.log" ]; then
            local stake_info=$(tail -n 50 /var/log/zano-pos-mining.log | grep "PoS mining" | tail -n 1)
            echo -e "${BLUE}Staking Status:${NC} $stake_info"
        fi
    else
        echo -e "${RED}Staking is not active${NC}"
    fi
}

show_wallet_balance() {
    if ! is_zanod_running; then
        echo -e "${RED}Zano daemon must be running to check balance${NC}"
        return 1
    fi

    if [ -z "$WALLET_NAME" ]; then
        read -p "Enter wallet name: " WALLET_NAME
    fi

    if ! is_wallet_exists "$WALLET_NAME"; then
        echo -e "${RED}Wallet $WALLET_NAME does not exist${NC}"
        return 1
    fi

    local balance_output
    balance_output=$(${ZANO_DIR}/simplewallet --wallet-file=${WALLET_NAME}.wallet --pass=${WALLET_PASSWORD} --command="balance")
    echo -e "${GREEN}$balance_output${NC}"
}

check_services_status() {
    echo -e "${BLUE}===== Zano Mining Services Status =====${NC}"
    for service in zanod tt-miner zano-pos-mining; do
        if systemctl is-active --quiet $service.service; then
            echo -e "${GREEN}● $service.service is running${NC}"
        else
            echo -e "${RED}○ $service.service is stopped${NC}"
        fi
        echo "---"
        systemctl status $service.service --no-pager | grep -A 2 "Active:"
        echo
    done
}

# Part 4: Daemon Management Functions

start_zanod() {
    log "Starting Zano daemon in background..."
    cd "$ZANO_DIR" || error "Failed to change to Zano directory"
    ${ZANO_DIR}/zanod > zanod_output.log 2>&1 &
    ZANOD_PID=$!
    log "Zano daemon started with PID: $ZANOD_PID"
    log "Waiting 10 seconds for blockchain sync..."
    sleep 10
}

stop_zanod() {
    if [ ! -z "$ZANOD_PID" ] && ps -p $ZANOD_PID > /dev/null; then
        log "Stopping Zanod (PID: $ZANOD_PID)"
        kill $ZANOD_PID
        wait $ZANOD_PID 2>/dev/null || true
    else
        log "No running Zanod process found with stored PID"
        pkill -f zanod || true
    fi
}

create_zano_wallet() {
    log "Creating Zano Wallet..."
    
    log "Generating wallet: ${WALLET_NAME}.wallet"
    


    start_zanod

    ${ZANO_DIR}/simplewallet --generate-new-wallet=${WALLET_NAME}.wallet <<EOF
${WALLET_PASSWORD}
EOF

    WALLET_ADDRESS=$(${ZANO_DIR}/simplewallet --wallet-file=${WALLET_NAME}.wallet <<EOF
${WALLET_PASSWORD}
address
exit
EOF
)

    WALLET_ADDRESS=$(echo "$WALLET_ADDRESS" | grep -oP 'Zx[a-zA-Z0-9]+' | head -n 1)

    log "Wallet created successfully!"
    echo -e "${BLUE}Wallet Address: ${WALLET_ADDRESS}${NC}"

    SEED_PHRASE=$(${ZANO_DIR}/simplewallet --wallet-file=${WALLET_NAME}.wallet <<EOF
${WALLET_PASSWORD}
show_seed
${WALLET_PASSWORD}
${SEED_PASSWORD}
${SEED_PASSWORD}
exit
EOF
)

    SEED_PHRASE=$(echo "$SEED_PHRASE" | grep -A1 "Remember, restoring a wallet from Secured Seed can only be done if you know its password." | tail -n1 | sed 's/\[Zano wallet.*$//')

    stop_zanod

    echo "Wallet Name: ${WALLET_NAME}" > "$ZANO_DIR/wallet-details.txt"
    echo "Wallet Address: ${WALLET_ADDRESS}" >> "$ZANO_DIR/wallet-details.txt"
    echo "Wallet Password: ${WALLET_PASSWORD}" >> "$ZANO_DIR/wallet-details.txt"
    echo "Seed Password: ${SEED_PASSWORD}" >> "$ZANO_DIR/wallet-details.txt"
    echo "Seed Phrase: ${SEED_PHRASE}" >> "$ZANO_DIR/wallet-details.txt"

    chmod 600 "$ZANO_DIR/wallet-details.txt"
}

collect_user_inputs() {
    echo -e "${BLUE}===== User Configuration =====${NC}"
    echo "This section will collect necessary information for your Zano setup."

    # Wallet setup options
    echo -e "\nWallet Setup Options:"
    echo "1) Create new wallet"
    echo "2) Import wallet from file"
    echo "3) Import wallet from seed phrase"
    read -p "Choose wallet setup method (1-3): " WALLET_SETUP_CHOICE

    case $WALLET_SETUP_CHOICE in
        1)  # Create new wallet
            CREATE_WALLET_YES="yes"
            read -p "Do you want to set your own wallet password? (y/n): " SET_OWN_WALLET_PASSWORD
            if [[ $SET_OWN_WALLET_PASSWORD =~ ^[Yy]$ ]]; then
                while true; do
                    read -s -p "Enter your wallet password: " WALLET_PASSWORD
                    echo
                    read -s -p "Confirm your wallet password: " WALLET_PASSWORD_CONFIRM
                    echo
                    
                    if [ "$WALLET_PASSWORD" = "$WALLET_PASSWORD_CONFIRM" ]; then
                        break
                    else
                        warn "Passwords do not match. Please try again."
                    fi
                done
            else
                WALLET_PASSWORD=$(pwgen -s 16 1)
                echo "A secure random password has been generated for your wallet."
            fi
            read -p "Do you want to set your own seed password? (y/n): " SET_OWN_SEED_PASSWORD
            if [[ $SET_OWN_SEED_PASSWORD =~ ^[Yy]$ ]]; then
                while true; do
                    read -s -p "Enter your seed password: " SEED_PASSWORD
                    echo
                    read -s -p "Confirm your seed password: " SEED_PASSWORD_CONFIRM
                    echo
                    
                    if [ "$SEED_PASSWORD" = "$SEED_PASSWORD_CONFIRM" ]; then
                        break
                    else
                        warn "Passwords do not match. Please try again."
                    fi
                done
            else
                SEED_PASSWORD=$(pwgen -s 16 1)
                echo "A secure random password has been generated for your wallet."
            fi
            read -p "Enter a name for your wallet (e.g., myzanowallet): " WALLET_NAME
            ;;
            
        2)  # Import wallet from file
            read -p "Enter the path to your wallet file: " WALLET_FILE_PATH
            if [ ! -f "$WALLET_FILE_PATH" ]; then
                error "Wallet file not found: $WALLET_FILE_PATH"
            fi
            read -s -p "Enter wallet password: " WALLET_PASSWORD
            echo
            WALLET_NAME=$(basename "$WALLET_FILE_PATH" .wallet)
            mkdir -p "$ZANO_DIR"
            cp "$WALLET_FILE_PATH" "$ZANO_DIR/${WALLET_NAME}.wallet"

            # Start zanod and get wallet address
            start_zanod
            WALLET_ADDRESS=$(${ZANO_DIR}/simplewallet --wallet-file=${WALLET_NAME}.wallet <<EOF
${WALLET_PASSWORD}
address
exit
EOF
)
            WALLET_ADDRESS=$(echo "$WALLET_ADDRESS" | grep -oP 'Zx[a-zA-Z0-9]+' | head -n 1)
            if [ -z "$WALLET_ADDRESS" ]; then
                error "Failed to extract wallet address"
            fi
            echo -e "${BLUE}Wallet Address: ${WALLET_ADDRESS}${NC}"
            stop_zanod
            ;;
            
        3)  # Import wallet from seed phrase
            read -p "Enter a name for your wallet (e.g., myzanowallet): " WALLET_NAME
            read -s -p "Enter wallet password: " WALLET_PASSWORD
            echo

            # Verify the password is not empty
            if [ -z "$WALLET_PASSWORD" ]; then
                error "Password cannot be empty"
            fi

            read -s -p "Enter seed password (if any, or press Enter): " SEED_PASSWORD
            echo
            echo "Paste your Zano seed phrase (all words in a single line, separated by spaces):"
            read -s SEED_WORDS
            
            # Start zanod for wallet restore
            start_zanod
            
            # Create temporary files with secure permissions
            TEMP_RESTORE_SCRIPT=$(mktemp)
            chmod 600 "$TEMP_RESTORE_SCRIPT"
            
            # Prepare restore commands
            cat > "$TEMP_RESTORE_SCRIPT" << EOF
$SEED_WORDS
$SEED_PASSWORD
EOF
            
            # Restore wallet from seed
            ${ZANO_DIR}/simplewallet --restore-wallet="${ZANO_DIR}/${WALLET_NAME}.wallet" \
                                    --password="${WALLET_PASSWORD}" < "$TEMP_RESTORE_SCRIPT"
            
            if [ $? -ne 0 ]; then
                shred -u "$TEMP_RESTORE_SCRIPT"
                error "Failed to restore wallet"
            fi
            
            # Get wallet address just for display
            WALLET_ADDRESS=$(${ZANO_DIR}/simplewallet --wallet-file="${ZANO_DIR}/${WALLET_NAME}.wallet" \
                                                    --password="${WALLET_PASSWORD}" --command="address")
            WALLET_ADDRESS=$(echo "$WALLET_ADDRESS" | grep -oP 'Zx[a-zA-Z0-9]+' | head -n 1)
            
            if [ -z "$WALLET_ADDRESS" ]; then
                shred -u "$TEMP_RESTORE_SCRIPT"
                error "Failed to extract wallet address"
            fi
            
            echo -e "\n${GREEN}Wallet successfully imported!${NC}"
            echo -e "${BLUE}Wallet Address: ${WALLET_ADDRESS}${NC}"
            
            # Secure cleanup
            shred -u "$TEMP_RESTORE_SCRIPT"
            stop_zanod
            ;;
                    
                *)
                    error "Invalid choice"
                    ;;
    esac

    # Common configuration for all setup methods
    read -p "Do you want to use pool mining? (y/n): " USE_POOL_MINING
    if [[ $USE_POOL_MINING =~ ^[Yy]$ ]]; then
        read -p "Enter worker name for pool mining: " POOL_WORKER_NAME
    fi

    read -p "Would you like to start the services after installation? (y/n): " START_SERVICES_AFTER_INSTALL

    # Save wallet information
    if [ ! -f "$ZANO_DIR/wallet-details.txt" ]; then
        echo "Wallet Name: ${WALLET_NAME}" > "$ZANO_DIR/wallet-details.txt"
        echo "Wallet Address: ${WALLET_ADDRESS}" >> "$ZANO_DIR/wallet-details.txt"
        echo "Wallet Password: ${WALLET_PASSWORD}" >> "$ZANO_DIR/wallet-details.txt"
        chmod 600 "$ZANO_DIR/wallet-details.txt"
    fi

    echo -e "${GREEN}Configuration completed successfully${NC}"
}

start_services() {
    log "Starting all Zano services..."
    sudo systemctl start zanod.service
    sleep 10
    sudo systemctl start tt-miner.service
    sudo systemctl start zano-pos-mining.service
    check_services_status
}

stop_services() {
    log "Stopping all Zano services..."
    sudo systemctl stop zano-pos-mining.service
    sudo systemctl stop tt-miner.service
    sudo systemctl stop zanod.service
    check_services_status
}

restart_services() {
    log "Restarting all Zano services..."
    stop_services
    sleep 5
    start_services
}

await_enter() {
    echo
    read -p "Press Enter to continue..."
}

# Part 5: Menu System

show_interactive_menu() {
    while true; do
        clear
        echo -e "${BLUE}╔════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║      Zano Mining & Staking         ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════╝${NC}"
        echo
        echo "1) Start mining and staking"
        echo "2) Show status of services"
        echo "3) Start the services"
        echo "4) Stop the services"
        echo "5) Restart the services"
        echo "6) Show Logs"
        echo "7) Delete Logs"
        echo "8) Exit"
        echo
        read -p "Select an option (1-8): " choice

        case $choice in
            1) main ;;
            2) check_services_status 
               show_mining_status
               show_staking_status
               await_enter ;;
            3) start_services
               await_enter ;;
            4) stop_services
               await_enter ;;
            5) restart_services
               await_enter ;;
            6) show_logs ;;
            7) delete_logs ;;
            8) 
                echo -e "${GREEN}Exiting...${NC}"
                exit 0 
                ;;
            *) 
                echo -e "${RED}Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

show_logs() {
    echo -e "${BLUE}===== Available Log Files =====${NC}"
    log_files=(
        "/var/log/zanod.log"                  # Zano daemon service log
        "/var/log/zanod.error.log"            # Zano daemon error log
        "/var/log/tt-miner.log"               # TT-miner log
        "/var/log/tt-miner.error.log"         # TT-miner error log
        "/var/log/zano-pos-mining.log"        # Staking log
        "/var/log/zano-pos-mining.error.log"  # Staking error log
    )

    # Display log files
    for i in "${!log_files[@]}"; do
        echo -e "${GREEN}[$i] ${log_files[$i]}${NC}"
    done

    # Get user selection
    read -p "Select a log file to view (0-$((${#log_files[@]}-1))): " log_selection

    # Validate selection
    if ! [[ "$log_selection" =~ ^[0-9]+$ ]] || [ "$log_selection" -lt 0 ] || [ "$log_selection" -ge "${#log_files[@]}" ]; then
        echo -e "${RED}Invalid selection. Exiting...${NC}"
        return
    fi

    # Display selected log file
    selected_log="${log_files[$log_selection]}"
    echo -e "${YELLOW}Displaying content of: $selected_log${NC}"
    echo

    # Check if the log file exists before attempting to print
    if [ -f "$selected_log" ]; then
        cat "$selected_log"
    else
        echo -e "${RED}Log file does not exist: $selected_log${NC}"
    fi

    echo
    read -p "Press Enter to continue..."
}

delete_logs() {
    local logs=(
        "/var/log/zanod.log"
        "/var/log/zanod.error.log"
        "/var/log/tt-miner.log"
        "/var/log/tt-miner.error.log"
        "/var/log/zano-pos-mining.log"
        "/var/log/zano-pos-mining.error.log"
    )

    echo "Available logs to delete:"
    for i in "${!logs[@]}"; do
        echo "[$i] ${logs[$i]}"
    done

    read -p "Enter the number of the log to delete (or 'all' to delete all logs): " choice

    if [[ "$choice" == "all" ]]; then
        for log in "${logs[@]}"; do
            if [ -f "$log" ]; then
                sudo rm "$log"
                echo "Deleted: $log"
            else
                echo "File not found: $log"
            fi
        done
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -lt ${#logs[@]} ]; then
        if [ -f "${logs[$choice]}" ]; then
            sudo rm "${logs[$choice]}"
            echo "Deleted: ${logs[$choice]}"
        else
            echo "File not found: ${logs[$choice]}"
        fi
    else
        echo "Invalid choice"
        return 1
    fi
}

# Part 6: Command Handling

handle_direct_command() {
    case "$1" in
        "create-wallet")
            install_dependencies
            download_zano_components
            create_zano_wallet
            ;;
        "start-zanod")
            if is_zanod_running; then
                echo -e "${YELLOW}Daemon is already running${NC}"
            else
                install_dependencies
                download_zano_components
                start_zanod
            fi
            ;;
        "stop-zanod")
            stop_zanod
            ;;
        "status")
            clear
            echo -e "${BLUE}═══ Zano Status ═══${NC}"
            check_services_status
            show_mining_status
            show_staking_status
            ;;
        "help")
            show_help
            ;;
        "install")
            install
            ;;
        "uninstall")
            uninstall
            ;;
        "build")
            main
            ;;
        start)
            start_services
            exit 0
            ;;
        stop)
            stop_services
            exit 0
            ;;
        restart)
            restart_services
            exit 0
            ;;
        logs)
            show_logs
            ;;
        delete-logs)
            delete_logs
            ;;
        help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown command: $1${NC}"
            show_help
            exit 1
            ;;
    esac
}

show_help() {
    echo -e "${BLUE}===== Zano Miner Script Help =====${NC}"
    echo -e "Usage: zanominer [COMMAND]"
    echo
    echo "Commands:"
    echo -e "${GREEN}  status${NC}         - Show status of all components"
    echo -e "${GREEN}  install${NC}        - Install script system-wide"
    echo -e "${GREEN}  uninstall${NC}      - Remove script and clean up"
    echo -e "${GREEN}  build${NC}          - Full installation and setup"
    echo -e "${GREEN}  start${NC}          - Start all Zano services"
    echo -e "${GREEN}  stop${NC}           - Stop all Zano services"
    echo -e "${GREEN}  restart${NC}        - Restart all Zano services"
    echo -e "${GREEN}  logs${NC}           - View service logs"
    echo -e "${GREEN}  delete-logs${NC}    - Delete service logs"
    echo -e "${GREEN}  create-wallet${NC}  - Create a new Zano wallet"
    echo -e "${GREEN}  start-zanod${NC}    - Start Zano daemon"
    echo -e "${GREEN}  stop-zanod${NC}     - Stop Zano daemon"
    echo -e "${GREEN}  help${NC}           - Show this help message"
    echo
    echo "Interactive Mode:"
    echo "Run without arguments to enter interactive menu mode with options:"
    echo "1) Start mining and staking"
    echo "2) Show status of services"
    echo "3) Start the services"
    echo "4) Stop the services"
    echo "5) Restart the services"
    echo "6) Show Logs"
    echo "7) Delete Logs"
    echo "8) Exit"
    echo
    echo "Examples:"
    echo "  zanominer               # Enter interactive mode"
    echo "  zanominer create-wallet # Create a new wallet"
    echo "  zanominer build         # Full installation"
    echo "  zanominer start         # Start all services"
    echo
    echo "Requirements:"
    echo "- Ubuntu Desktop"
    echo "- NVIDIA GPU (for optimal mining)"
    echo "- Sudo privileges"
    echo
    echo "For more information, visit:"
    echo "https://github.com/Mik-TF/zanominer"
}

install() {
    echo
    echo -e "${GREEN}Installing Zano Miner...${NC}"
    if sudo -v; then
        sudo rm /usr/local/bin/zanominer
        sudo cp "$0" /usr/local/bin/zanominer
        sudo chown root:root /usr/local/bin/zanominer
        sudo chmod 755 /usr/local/bin/zanominer

        echo -e "${PURPLE}zanominer has been installed successfully.${NC}"
        echo -e "You can now use ${GREEN}zanominer${NC} command from anywhere."
        echo -e "Use ${BLUE}zanominer help${NC} to see the commands."
    else
        echo -e "${RED}Error: Failed to obtain sudo privileges. Installation aborted.${NC}"
        exit 1
    fi
}

uninstall() {
    echo -e "${GREEN}Uninstalling zanominer...${NC}"
    if sudo -v; then
        stop_services
        
        sudo systemctl disable zanod.service tt-miner.service zano-pos-mining.service 2>/dev/null
        sudo rm -f /etc/systemd/system/zanod.service
        sudo rm -f /etc/systemd/system/tt-miner.service
        sudo rm -f /etc/systemd/system/zano-pos-mining.service
        sudo systemctl daemon-reload
        
        sudo rm -f /usr/local/bin/zanominer

        read -p "Remove all Zano project data? (y/n): " REMOVE_DATA
        if [[ $REMOVE_DATA =~ ^[Yy]$ ]]; then
            rm -rf "$ZANO_DIR"
            echo "Zano project data removed."
        fi

        echo -e "${GREEN}Uninstallation completed successfully.${NC}"
    else
        echo -e "${RED}Error: Failed to obtain sudo privileges. Uninstallation aborted.${NC}"
        exit 1
    fi
}

# Part 7: Integration & Main Entry Point

check_prerequisites() {
    if [ "$(id -u)" = "0" ]; then
        error "Please do not run this script as root. Use sudo when prompted."
    fi

    if ! grep -q "Ubuntu" /etc/os-release; then
        warn "This script is designed for Ubuntu. Other distributions may not work correctly."
    fi

    local required_commands=("curl" "wget" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            error "Required command '$cmd' not found. Please install it first."
        fi
    done
}

main() {
    clear
    echo -e "${BLUE}===== Zano Complete Setup =====${NC}"
    
    check_prerequisites
    
    if [ -z "$WALLET_NAME" ]; then
        collect_user_inputs
    fi
    
    install_dependencies
    download_zano_components
    
    if [ "$CREATE_WALLET_YES" = "yes" ]; then
        create_zano_wallet
    fi
    
    setup_tt_miner
    create_service_scripts
    create_systemd_services
    
    if [[ $START_SERVICES_AFTER_INSTALL =~ ^[Yy]$ ]]; then
        start_services
    fi
    
    log "Installation complete!"
}

# Script execution starts here
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap 'echo -e "\n${RED}Script interrupted${NC}"; exit 1' SIGINT SIGTERM
    
    if [ $# -eq 0 ]; then
        show_interactive_menu
    else
        handle_direct_command "$1"
    fi
fi