import socket
import threading

# --- SERVER CONFIGURATION ---
#Enabling listening on all network interfaces 
HOST = '0.0.0.0' 
#Specific port for our application
PORT = 5000      

def handle_client(client_socket, client_address):
    #This function runs every time a new client connects. It handles all communication with that client.
    
    print(f"[NEW CONNECTION] {client_address} just connected.")
    
    try:
        # The connection stays open in this infinite loop
        while True:
            # Wait to receive data from the Flutter app (up to 1024 bytes)
            data = client_socket.recv(1024)
            
            # If the data is empty, the client disconnected normally
            if not data:
                break 
            
            # Decode the raw bytes back into a readable string
            message = data.decode('utf-8')
            print(f"[{client_address[0]}] says: {message}")
            
    except ConnectionResetError:
        # This catches the "Ghost Connection" if the connection is disrupted.
        print(f"[DISCONNECTED] {client_address} was unplugged violently.")
    finally:
        # Always clean up and close the socket when the user leaves
        client_socket.close()
        print(f"[CLOSED] Connection with {client_address} terminated.")

def start_server():
    #This portion listens for connections/requests from Flutter apps and spawns a new thread for each one.
    # 1. Create the Socket (AF_INET = IPv4, SOCK_STREAM = TCP)
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    
    # 2. Bind the Socket to our HOST and PORT
    server.bind((HOST, PORT))
    
    # 3. Start Listening (The '5' means up to 5 people can wait in line)
    server.listen(5)
    print(f"[LISTENING] Server is listening on {HOST}:{PORT}")
    
    while True:
        #The server is waiting for communication from a user. When a user connects, it returns a new socket for that user and their address.
        client_socket, client_address = server.accept()
        
        # 5. Hand the user off to their own dedicated thread so the server can go back to listening
        thread = threading.Thread(target=handle_client, args=(client_socket, client_address))
        thread.start()
        
        # Print how many users are currently in the system 
        # 1 Thread reserved for listening so we have to - it from the total number of threads to know the number of users active.
        print(f"[ACTIVE CONNECTIONS] {threading.active_count() - 1}")

if __name__ == "__main__":
    print("[STARTING] Server is starting up...")
    start_server()