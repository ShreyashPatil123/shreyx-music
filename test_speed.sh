URL=$(logcat -d -s ShrexNewPipe | grep "RESOLVED URL:" | tail -n 1 | sed "s/.*RESOLVED URL: //")
echo "--- Testing HEAD / Range ---"
curl -s -k -I -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36" -r 0-1048575 "$URL"
echo "--- Testing 1MB Download to /data/local/tmp ---"
time curl -s -k -r 0-1048575 -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36" "$URL" -o /data/local/tmp/test_chunk.bin
ls -lh /data/local/tmp/test_chunk.bin
