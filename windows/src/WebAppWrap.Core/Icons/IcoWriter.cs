namespace WebAppWrap.Core.Icons;

/// <summary>
/// Minimal .ico reader/writer using PNG-compressed frames, which Windows supports at every size.
/// </summary>
public static class IcoWriter
{
    public static byte[] Write(IReadOnlyList<(int Size, byte[] Png)> frames)
    {
        using var stream = new MemoryStream();
        using var writer = new BinaryWriter(stream);

        // ICONDIR: reserved, type (1 = icon), image count.
        writer.Write((ushort)0);
        writer.Write((ushort)1);
        writer.Write((ushort)frames.Count);

        var offset = 6 + 16 * frames.Count;
        foreach (var (size, png) in frames)
        {
            // ICONDIRENTRY. A width/height byte of 0 means 256.
            writer.Write((byte)(size >= 256 ? 0 : size));
            writer.Write((byte)(size >= 256 ? 0 : size));
            writer.Write((byte)0);   // palette colors
            writer.Write((byte)0);   // reserved
            writer.Write((ushort)1); // color planes
            writer.Write((ushort)32);// bits per pixel
            writer.Write(png.Length);
            writer.Write(offset);
            offset += png.Length;
        }
        foreach (var (_, png) in frames) writer.Write(png);

        writer.Flush();
        return stream.ToArray();
    }

    /// <summary>The image data of the largest frame (PNG or BMP-in-ICO payload), or null if not an icon.</summary>
    public static byte[]? LargestFrame(byte[] ico)
    {
        if (ico.Length < 6 || BitConverter.ToUInt16(ico, 0) != 0 || BitConverter.ToUInt16(ico, 2) != 1) return null;
        var count = BitConverter.ToUInt16(ico, 4);
        byte[]? best = null;
        var bestSize = -1;
        for (var i = 0; i < count; i++)
        {
            var entry = 6 + 16 * i;
            if (entry + 16 > ico.Length) break;
            var size = ico[entry] == 0 ? 256 : ico[entry];
            var length = BitConverter.ToInt32(ico, entry + 8);
            var offset = BitConverter.ToInt32(ico, entry + 12);
            if (size <= bestSize || offset < 0 || length <= 0 || offset + length > ico.Length) continue;
            // Only PNG frames decode directly; skip classic BMP frames.
            if (length < 8 || ico[offset] != 0x89 || ico[offset + 1] != (byte)'P') continue;
            best = ico[offset..(offset + length)];
            bestSize = size;
        }
        return best;
    }
}
