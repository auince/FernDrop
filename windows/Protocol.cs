using System.Security.Cryptography;
using System.Text.Json;
namespace FernDrop;
// Wire-compatible with CryptoKit AES.GCM.SealedBox.combined. No production key is embedded.
public static class WireCrypto {
 public static byte[] Encrypt(ReadOnlySpan<byte> clear,ReadOnlySpan<byte> key) {
  if(key.Length!=32)throw new ArgumentException("32-byte key required");
  byte[] wire=new byte[12+clear.Length+16];RandomNumberGenerator.Fill(wire.AsSpan(0,12));
  using var aes=new AesGcm(key,16);aes.Encrypt(wire.AsSpan(0,12),clear,wire.AsSpan(12,clear.Length),wire.AsSpan(12+clear.Length,16));return wire;
 }
 public static byte[] Decrypt(ReadOnlySpan<byte> wire,ReadOnlySpan<byte> key) {
  if(key.Length!=32||wire.Length<29)throw new ArgumentException("Invalid key or wire length");
  byte[] clear=new byte[wire.Length-28];using var aes=new AesGcm(key,16);aes.Decrypt(wire[..12],wire.Slice(12,clear.Length),wire[^16..],clear);return clear;
 }
}
public sealed record WireFile(string name,string data);
public sealed record Envelope(int version,string id,string senderID,string senderName,double createdAt,string kind,string text,WireFile[] files,string? ticket=null,bool? allowRelay=null);
public sealed record BridgeRequest(string id,string method,JsonElement args);
