using System.Text.Json;using System.Text;using System.Security.Cryptography;using FernDrop;
if(args.Length!=1){Console.Error.WriteLine("Usage: ProtocolCheck crypto-fixture.json");return 2;}
using var fixture=JsonDocument.Parse(File.ReadAllText(args[0]));var f=fixture.RootElement;
var key=Convert.FromBase64String(f.GetProperty("testKey").GetString()!);var wire=Convert.FromBase64String(f.GetProperty("wireBase64").GetString()!);
var clear=WireCrypto.Decrypt(wire,key);if(Encoding.UTF8.GetString(clear)!=f.GetProperty("plaintext").GetString())throw new Exception("Fixture mismatch");
var roundtrip=WireCrypto.Decrypt(WireCrypto.Encrypt(clear,key),key);if(!roundtrip.SequenceEqual(clear))throw new Exception("Roundtrip failed");
wire[14]^=1;try{WireCrypto.Decrypt(wire,key);throw new Exception("Tampered data accepted");}catch(CryptographicException){}
Console.WriteLine("PASS: shared protocol fixture, AES-GCM roundtrip and tamper rejection");return 0;
