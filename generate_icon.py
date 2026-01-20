#!/usr/bin/env python3
"""
Generate macOS .icns icon file from source image
Requires Pillow: pip3 install Pillow
"""

from PIL import Image
import os
import subprocess
import sys

def generate_iconset(source_image, output_dir):
    """Generate all required icon sizes for macOS"""
    
    # macOS icon sizes
    sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    
    # Ensure output directory exists
    os.makedirs(output_dir, exist_ok=True)
    
    # Open source image
    img = Image.open(source_image)
    
    # Generate each size
    for size, filename in sizes:
        resized = img.resize((size, size), Image.Resampling.LANCZOS)
        output_path = os.path.join(output_dir, filename)
        resized.save(output_path, "PNG")
        print(f"Generated: {filename} ({size}x{size})")
    
    return output_dir

def create_icns(iconset_dir, output_icns):
    """Convert iconset to .icns file using macOS iconutil"""
    try:
        subprocess.run(
            ["iconutil", "-c", "icns", iconset_dir, "-o", output_icns],
            check=True
        )
        print(f"\n✓ Created: {output_icns}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error creating .icns: {e}")
        return False

if __name__ == "__main__":
    # Paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    source_image = os.path.join(script_dir, "icon_source.png")
    iconset_dir = os.path.join(script_dir, "ScreenshotManager.iconset")
    output_icns = os.path.join(script_dir, "ScreenshotManager.icns")
    
    # Check if source exists
    if not os.path.exists(source_image):
        print(f"Error: Source image not found at {source_image}")
        print("Please place your 1024x1024 icon as 'icon_source.png' in the project root")
        sys.exit(1)
    
    print("Generating icon set...")
    generate_iconset(source_image, iconset_dir)
    
    print("\nConverting to .icns...")
    if create_icns(iconset_dir, output_icns):
        print("\n✓ Icon generation complete!")
        print(f"  - Iconset: {iconset_dir}")
        print(f"  - ICNS file: {output_icns}")
    else:
        print("\n✗ Failed to create .icns file")
        sys.exit(1)
