import sqlite3
import bcrypt
import os

# 1. Configuration
DB_PATH = os.path.join(os.path.dirname(__file__), '..', 'data', 'im_system.db')

# 2. Security Functions
def hash_password(password):
    # Convert the string password into raw bytes
    password_bytes = password.encode('utf-8')
    
    # Generate a random salt
    salt = bcrypt.gensalt()
    
    # Hash the password using the generated salt
    hashed_bytes = bcrypt.hashpw(password_bytes, salt)
    
    # Convert the bytes back into a string for storing in DB
    return hashed_bytes.decode('utf-8')

# 3. Database Initialization
def init_db():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL
        )
    ''')
    
    conn.commit()
    conn.close()
    print("[DATABASE] SQLite Database initialized securely.")

# 4. Registration Logic
def register_user(username, password):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    try:
        secure_hash = hash_password(password)
        
        cursor.execute("INSERT INTO users (username, password_hash) VALUES (?, ?)", 
                       (username, secure_hash))
        conn.commit()
        print(f"[DATABASE] User '{username}' registered successfully.")
        return True
        
    except sqlite3.IntegrityError:
        print(f"[DATABASE] Registration failed: Username '{username}' is already taken.")
        return False
        
    finally:
        conn.close()
        
        
def login_user(username, password):
   
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    try:
        # 1. Fetch the stored hash for this specific user
        cursor.execute("SELECT password_hash FROM users WHERE username = ?", (username,))
        result = cursor.fetchone()
        
       
        if result is None:
            print(f"[DATABASE] Login failed: User '{username}' does not exist.")
            return False
            
        # Extract the string from the tuple so that the bcrypt function does not crash as the result variable is a tuple.
        stored_hash = result[0]
        
        # 3. Use bcrypt to compare the raw password with the stored hash
        # We must encode both back to bytes for bcrypt to read them
        if bcrypt.checkpw(password.encode('utf-8'), stored_hash.encode('utf-8')):
            print(f"[DATABASE] Login successful for user: {username}")
            return True
        else:
            print(f"[DATABASE] Login failed: Incorrect password for '{username}'.")
            return False
            
    finally:
        conn.close()
