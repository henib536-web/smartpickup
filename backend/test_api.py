import urllib.request
try:
    req = urllib.request.Request("http://127.0.0.1:8000/api/admin/users/4/rides")
    response = urllib.request.urlopen(req)
    print("Status:", response.status)
    print("Data:", response.read().decode('utf-8')[:100])
except Exception as e:
    print("Error:", e)
