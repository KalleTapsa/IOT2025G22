import bmp280
import dht
from machine import Pin, I2C
import time, network, socket
from config import SSID, PASSWORD, DHT_PIN, I2C_SCL, I2C_SDA
import gc
try:
    import uos as os  # MicroPython
except ImportError:
    import os

# --- Settings ---
SAMPLE_INTERVAL = 60         #Sample interval in seconds
HISTORY_FILE = 'history.csv'
MAX_HISTORY_BYTES = 350 * 1024

# Last sample
last_sample_line = None

# --- I2C and sensors ---
i2c = I2C(1, scl=Pin(I2C_SCL), sda=Pin(I2C_SDA), freq=100_000)
try:
    bmp = bmp280.BMP280(i2c)
except OSError as e:
    print("BMP280 init failed:", e)
    bmp = None

dht_sensor = dht.DHT22(Pin(DHT_PIN))


# --- History ---

def trim_history_by_size():
    
    DROP_LINES = 1000

    try:
        st = os.stat(HISTORY_FILE)
    except OSError:
        return

    size = st[6]
    if size <= MAX_HISTORY_BYTES:
        return

    print("Trimming history: dropping first", DROP_LINES, "lines. Current size:", size)

    tmp_name = HISTORY_FILE + ".tmp"

    try:
        drop_bytes = 0
        lines_read = 0

        with open(HISTORY_FILE, "rb") as fin:
            while lines_read < DROP_LINES:
                line = fin.readline()
                if not line:
                    break
                drop_bytes += len(line)
                lines_read += 1

        if drop_bytes <= 0:
            return

        print("Dropping", lines_read, "lines (", drop_bytes, "bytes )")

        with open(HISTORY_FILE, "rb") as fin, open(tmp_name, "wb") as fout:
            fin.seek(drop_bytes)
            while True:
                chunk = fin.read(512)
                if not chunk:
                    break
                fout.write(chunk)

        try:
            os.remove(HISTORY_FILE)
        except OSError:
            pass

        try:
            os.rename(tmp_name, HISTORY_FILE)
        except OSError as e:
            print("Rename failed:", e)

            try:
                with open(tmp_name, "rb") as fin, open(HISTORY_FILE, "wb") as fout:
                    while True:
                        chunk = fin.read(512)
                        if not chunk:
                            break
                        fout.write(chunk)
                try:
                    os.remove(tmp_name)
                except OSError:
                    pass
            except Exception as e2:
                print("Fallback copy failed:", e2)

        gc.collect()

    except Exception as e:
        print("Failed to trim history by size:", e)
        try:
            os.remove(tmp_name)
        except OSError:
            pass


def add_to_history(sample):
    """Add to CSV file and trim if needed."""
    global last_sample_line

    line = f"{sample['timestamp']},{sample['bmp_pressure']},{sample['dht_temp']},{sample['dht_humidity']}\n"
    last_sample_line = line

    try:
        with open(HISTORY_FILE, "a") as f:
            f.write(line)
        trim_history_by_size()
    except Exception as e:
        print("Failed to write history:", e)


def clear_history_file():
    """Clear history file."""
    global last_sample_line
    try:
        with open(HISTORY_FILE, "w") as f:
            pass
        last_sample_line = None
        return True
    except Exception as e:
        print("Failed to clear history:", e)
        return False


# --- Sensor read ---

def read_sensors():
    # BMP280
    if bmp is not None:
        try:
            bmp_pressure = bmp.pressure
        except OSError as e:
            print("BMP280 read failed:", e)
            bmp_pressure = None
    else:
        bmp_pressure = None

    # DHT22
    try:
        dht_sensor.measure()
        dht_temp = dht_sensor.temperature()
        dht_hum = dht_sensor.humidity()
    except OSError as e:
        print("DHT22 read failed:", e)
        dht_temp = None
        dht_hum = None

    return {
        "bmp_pressure": bmp_pressure,
        "dht_temp": dht_temp,
        "dht_humidity": dht_hum,
        "timestamp": time.time()
    }


# --- Wi-Fi & HTTP ---

def connect_wifi():
    wlan = network.WLAN(network.STA_IF)
    wlan.active(True)
    wlan.connect(SSID, PASSWORD)
    print("Connecting to Wi-Fi...")
    while not wlan.isconnected():
        time.sleep(0.5)
    print("Connected:", wlan.ifconfig())
    return wlan


def start_http_server():
    addr = socket.getaddrinfo('0.0.0.0', 80)[0][-1]
    s = socket.socket()
    try:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    except:
        pass

    s.bind(addr)
    s.listen(1)
    s.settimeout(0.1)
    print("HTTP server running on port 80")

    last_sample_ms = time.ticks_ms()

    while True:
        now_ms = time.ticks_ms()

        if time.ticks_diff(now_ms, last_sample_ms) >= SAMPLE_INTERVAL * 1000:
            print("Taking sample...")
            sample = read_sensors()
            add_to_history(sample)
            last_sample_ms = now_ms

        try:
            try:
                conn, c_addr = s.accept()
            except OSError:
                continue

            print("Client connected:", c_addr)

            try:
                conn.settimeout(1.0)
            except:
                pass

            try:
                req = conn.recv(1024)
            except OSError as e:
                print("recv error:", e)
                conn.close()
                continue

            if not req:
                conn.close()
                continue

            try:
                req_str = req.decode()
            except:
                req_str = ""

            gc.collect()

            # --- /latest ---
            if "GET /latest" in req_str:
                try:
                    if last_sample_line is not None:
                        body = last_sample_line
                    else:
                        body = ""
                        try:
                            with open(HISTORY_FILE) as f:
                                for line in f:
                                    body = line
                        except OSError:
                            body = ""

                    header = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n"
                    conn.send(header.encode())
                    if body:
                        conn.send(body.encode())
                except Exception as e:
                    print("Error in /latest:", e)
                    try:
                        conn.send(b"HTTP/1.1 500 Internal Error\r\nConnection: close\r\n\r\n")
                    except:
                        pass

            # --- /history ---
            elif "GET /history" in req_str:
                try:
                    conn.send(b"HTTP/1.1 200 OK\r\n"
                              b"Content-Type: text/plain\r\n"
                              b"Connection: close\r\n"
                              b"\r\n")

                    CHUNK_SIZE = 1024
                    with open(HISTORY_FILE, "rb") as f:
                        while True:
                            chunk = f.read(CHUNK_SIZE)
                            if not chunk:
                                break
                            conn.send(chunk)

                    gc.collect()

                except Exception as e:
                    print("Error in /history:", e)

            # --- /clear_history ---
            elif "GET /clear_history" in req_str:
                success = clear_history_file()
                if success:
                    conn.send(b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nHistory cleared.\n")
                else:
                    conn.send(b"HTTP/1.1 500 Internal Error\r\nConnection: close\r\n\r\nFailed to clear history.\n")

            else:
                conn.send(b"HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n")

        except Exception as e:
            print("Unhandled error in request handler:", e)

        finally:
            try:
                conn.close()
            except:
                pass


def main():
    connect_wifi()
    trim_history_by_size()
    start_http_server()


main()