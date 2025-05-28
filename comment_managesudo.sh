#!/bin/bash
# Tells the shell to interpret this script using bash

# ============================== CONSTANTS ==============================

SUDOERS_DIR="/etc/sudoers.d"  # Directory for custom sudo rules per user
TMP_FILE="/tmp/managesudo_tmp"  # Temporary file to build and test sudoers syntax
LOG_FILE="/var/log/managesudo.log"  # Custom log file for all script actions

# ============================ ROOT CHECK ===============================

# Check if the current effective user ID (EUID) is not 0 (not root)
if [[ "$EUID" -ne 0 ]]; then
    echo "Please run this script with sudo."  # Prompt user to rerun as sudo
    exit 1  # Exit with status 1 to indicate error
fi

# ======================== LOGGING FUNCTION =============================

function log_action() {
    local action="$1"  # Store the first function argument in local variable 'action'
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"  # Get current timestamp in readable format

    # If log file doesn't already exist
    if [[ ! -f "$LOG_FILE" ]]; then
        sudo touch "$LOG_FILE"  # Create it as root
        sudo chown root:devops "$LOG_FILE"  # Make it readable to root and group 'devops'
        sudo chmod 640 "$LOG_FILE"  # rw-r----- permissions
        echo "$timestamp Log file created." >> "$LOG_FILE"  # Log creation time
    fi

    echo "$timestamp $action" >> "$LOG_FILE"  # Append the action to the log file
}

# ========================= PRINT LOG FUNCTION ==========================

function print_log() {
    cat "$LOG_FILE"  # Print the entire contents of the log file
}

# ===================== PERMISSION SELECTION MENU ======================

function choose_permissions() {
    local username="$1"  # Capture username passed to the function

    echo "Choose sudo permission levels for $username"
    echo "1) Full access"
    echo "2) Command Restricted"

    while true; do
        read -rp "Enter your choice 1 or 2:" choice  # Prompt user for a selection

        case "$choice" in
            1)
                # Full sudo access with no password prompt
                echo "$username ALL=(ALL) NOPASSWD:ALL" > "$TMP_FILE"
                echo "Full sudo access granted to $username"
                break  # Exit the loop
                ;;
            2)
                # Restricted/Custom access placeholder
                echo "Not finished..."
                echo "custom access"
                break
                ;;
            *)
                echo "Invalid choice. Enter 1 or 2"  # Catch all other inputs
                ;;
        esac
    done
}

# ====================== ADD USER TO SUDOERS ===========================

function add_user() {
    # Loop until valid username is entered
    while true; do
        read -rp "Enter the username you want to add to sudoers: " username
        echo "$username"

        # Check if username input is empty
        if [[ -z "$username" ]]; then
            echo "Username cannot be empty."

        # Check if username exists in /etc/passwd
        elif ! grep -q "^$username:" /etc/passwd; then
            echo "User '$username' not found in /etc/passwd."
            continue  # Prompt again
        else
            echo "Valid username."
            break  # Valid input, break loop
        fi
    done

    choose_permissions "$username"  # Ask what level of sudo access to give

    # Prevent duplicate sudo entries
    if [[ -f "$SUDOERS_DIR/managesudo_$username" ]]; then
        echo "Sudo permissions already exist for this user."
        return
    fi

    # Validate sudo syntax using visudo in check mode
    if visudo -cf "$TMP_FILE"; then
        sudo cp "$TMP_FILE" "$SUDOERS_DIR/managesudo_$username"  # Move temp to proper file
        sudo chmod 440 "$SUDOERS_DIR/managesudo_$username"  # Secure permissions: r--r----- 
        echo "Sudo privileges added for $username."
    else
        echo "Invalid sudoers entry. Exiting."
    fi

    rm -f "$TMP_FILE"  # Delete the temporary file

    log_action "$username added by $SUDO_USER."  # Log who added the user
}

# ===================== REMOVE USER FROM SUDOERS ========================

function remove_user() {
    read -rp "Enter the username you want to remove from sudoers: " username

    if [[ -z "$username" ]]; then
        echo "username cannot be empty"
        return
    fi

    # Protect critical system users from being removed
    if [[ "$username" == "ec2-user" || "$username" == "root" ]]; then
        echo " '$username' cannot be removed."
        return
    fi

    # Prevent user from revoking their own sudo access
    if [[ "$username" == "$SUDO_USER" ]]; then
        echo "You cannot remove your own sudo privileges."
        return
    fi

    userfile="$SUDOERS_DIR/managesudo_$username"  # Path to user's sudo file

    sudo ls -l "$userfile"  # Print info (for debug)

    if [[ -e "$userfile" ]]; then
        echo "File exists. Attempting to remove"
        sudo rm -f "$userfile"  # Force remove
        echo "Removed sudo access for $username."
    else
        echo "No entry found for $username."
    fi

    log_action "$username removed by $SUDO_USER."  # Log the action
}

# ====================== USER LISTING FUNCTION ==========================

function list_users() {
    echo ""
    echo "=== List Users Menu ==="
    echo "1) Show all users"
    echo "2) Show all users with sudo access"
    echo "3) Back to Main Menu"
    read -rp "Choose an option 1-3" choice

    case $choice in
        1)
            echo "All system users:"
            awk -F: '{ print $1 }' /etc/passwd  # Print only the username column from /etc/passwd
            ;;
        2)
            echo "Users with sudo access:"
            sudo ls -l "$SUDOERS_DIR"  # List files that define sudo access per user
            ;;
        3)
            echo "Going back to Main Menu..."
            return  # Exit function
            ;;
        *)
            echo "Invalid option."
            ;;
    esac

    log_action "$SUDO_USER Generated list of users."  # Log who accessed list
}

# ====================== GROUP MODIFICATION ==============================

function modify_groups() {
    read -rp "Enter the username you wish to modify groups: " username

    echo "Current groups for $username:"
    groups "$username"  # Display groups the user belongs to

    echo "Select an option"
    echo "1) Add user to a group"
    echo "2) Remove user from a group"
    echo "3) Exit"
    read -rp "Choose an option 1-3: " choice

    case "$choice" in
        1)
            read -rp "Enter a group name to add to: " groupname

            if [[ -z "$groupname" ]]; then
                echo "Group name cannot be empty"
                return
            fi

            if ! getent group "$groupname"; then
                echo "The group '$groupname' does not exist."  # Check group existence
                return
            fi

            sudo usermod -aG "$groupname" "$username"  # Append user to group
            echo "User '$username' added to group '$groupname'"
            echo "User is in the following groups: "
            groups "$username"

            log_action "$SUDO_USER added $username to $groupname."
            ;;
        2)
            read -rp "Enter a group name to remove: " groupname

            if [[ -z "$groupname" ]]; then
                echo "Group name cannot be empty"
                return
            fi

            if ! getent group "$groupname"; then
                echo "The group '$groupname' does not exist."
                return
            fi

            sudo gpasswd -d "$username" "$groupname"  # Delete user from group
            echo "User '$username' has been deleted from '$groupname';"
            echo "user is in the following groups: "
            groups "$username"

            log_action "$SUDO_USER removed $username from $groupname"
            ;;
        3)
            echo "Exiting..."
            return
            ;;
        *)
            echo "Invalid choice input number 1-3"
            return
            ;;
    esac
}

# ========================== MAIN MENU ==================================

function main_menu() {
    while true; do
        echo ""
        echo "Welcome $SUDO_USER"
        echo "=== sudo Manager =="
        echo "1) Add User to Sudoers"
        echo "2) Remove a user from sudoers"
        echo "3) Modify groups"
        echo "4) List current sudoers"
        echo "5) Print log file"
        echo "6) Exit"
        read -rp "Choose an option from the menu: " choice

        case $choice in
            1) add_user ;;
            2) remove_user ;;
            3) modify_groups ;;
            4) list_users ;;
            5) print_log ;;
            6) echo "Exiting"; exit 0 ;;  # Exit the script cleanly
            *) echo "Invalid option. Please enter a number 1-5." ;;
        esac
    done
}

# =========================== SCRIPT START ==============================

main_menu  # Launch the interactive menu loop


