[[ -d Clibwebsockets ]] && rm -rf Clibwebsockets
git clone git://github.com/NobodyNada/Clibwebsockets || exit 1

echo "Generating library..."
swiftc -IClibwebsockets -L/usr/local/lib -I/usr/local/opt/openssl/include -I/usr/local/include -emit-library -emit-object Sources/SwiftChatSE/*.swift -module-name SwiftChatSE || exit 1
ar rcs libSwiftChatSE.a *.o || exit 1
rm *.o
echo "Generating swiftmodule..."
swiftc -IClibwebsockets -L/usr/local/lib -I/usr/local/opt/openssl/include -I/usr/local/include -emit-module Sources/SwiftChatSE/*.swift -module-name SwiftChatSE || exit 1
