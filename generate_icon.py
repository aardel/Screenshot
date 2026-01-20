#!/usr/bin/env python3
"""
Generate a translucent macOS-style icon for Screenshot Manager
Creates all required icon sizes and packages them into an .iconset
"""

from PIL import Image, ImageDraw, ImageFilter
import os
import math

def create_icon(size):
    """Create a single icon at the specified size"""
    # Create a transparent image
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Calculate dimensions
    padding = size * 0.1
    icon_size = size - (padding * 2)
    center = size / 2
    
    # Create a rounded rectangle background with gradient effect
    # Using a translucent background with blur effect
    bg_size = icon_size * 0.95
    bg_padding = (size - bg_size) / 2
    
    # Draw a soft, translucent rounded rectangle background
    bg_rect = [
        bg_padding,
        bg_padding,
        size - bg_padding,
        size - bg_padding
    ]
    
    # Create a gradient-like effect using multiple layers
    # Base translucent background with a subtle color tint
    draw.rounded_rectangle(
        bg_rect,
        radius=size * 0.2,
        fill=(240, 245, 255, 200)  # Semi-transparent light blue-white
    )
    
    # Add a subtle colorful border with gradient effect
    border_width = max(2, size // 48)
    # Draw border with gradient colors
    for i in range(border_width):
        alpha = int(150 - i * 20)
        color = (
            int(100 + i * 5),
            int(150 + i * 3),
            int(255 - i * 2),
            alpha
        )
        offset = i
        border_rect = [
            bg_rect[0] + offset,
            bg_rect[1] + offset,
            bg_rect[2] - offset,
            bg_rect[3] - offset
        ]
        draw.rounded_rectangle(
            border_rect,
            radius=size * 0.2 - offset * 0.5,
            outline=color,
            width=1
        )
    
    # Draw the screenshot symbol - a camera/frame icon
    # Main frame (representing a screenshot)
    frame_size = icon_size * 0.6
    frame_padding = (icon_size - frame_size) / 2
    frame_x = center - frame_size / 2
    frame_y = center - frame_size / 2 - size * 0.05  # Slightly above center
    
    # Outer frame with colorful gradient effect
    frame_thickness = max(2, size // 32)
    
    # Draw colorful frame with vibrant gradient colors
    # Draw each side with a gradient
    num_steps = max(4, size // 32)
    
    # Top side - colorful gradient
    for i in range(num_steps):
        step_width = frame_size / num_steps
        x1 = frame_x + i * step_width
        x2 = frame_x + (i + 1) * step_width
        angle = (i / num_steps) * 2 * math.pi
        r = int(128 + 127 * math.sin(angle))
        g = int(128 + 127 * math.sin(angle + 2 * math.pi / 3))
        b = int(128 + 127 * math.sin(angle + 4 * math.pi / 3))
        draw.rectangle([x1, frame_y + frame_size - frame_thickness, x2, frame_y + frame_size], fill=(r, g, b, 255))
    
    # Right side
    for i in range(num_steps):
        step_height = frame_size / num_steps
        y1 = frame_y + frame_size - (i + 1) * step_height
        y2 = frame_y + frame_size - i * step_height
        angle = (0.5 + i / num_steps) * 2 * math.pi
        r = int(128 + 127 * math.sin(angle))
        g = int(128 + 127 * math.sin(angle + 2 * math.pi / 3))
        b = int(128 + 127 * math.sin(angle + 4 * math.pi / 3))
        draw.rectangle([frame_x + frame_size - frame_thickness, y1, frame_x + frame_size, y2], fill=(r, g, b, 255))
    
    # Bottom side
    for i in range(num_steps):
        step_width = frame_size / num_steps
        x1 = frame_x + frame_size - (i + 1) * step_width
        x2 = frame_x + frame_size - i * step_width
        angle = (1.0 + i / num_steps) * 2 * math.pi
        r = int(128 + 127 * math.sin(angle))
        g = int(128 + 127 * math.sin(angle + 2 * math.pi / 3))
        b = int(128 + 127 * math.sin(angle + 4 * math.pi / 3))
        draw.rectangle([x1, frame_y, x2, frame_y + frame_thickness], fill=(r, g, b, 255))
    
    # Left side
    for i in range(num_steps):
        step_height = frame_size / num_steps
        y1 = frame_y + i * step_height
        y2 = frame_y + (i + 1) * step_height
        angle = (1.5 + i / num_steps) * 2 * math.pi
        r = int(128 + 127 * math.sin(angle))
        g = int(128 + 127 * math.sin(angle + 2 * math.pi / 3))
        b = int(128 + 127 * math.sin(angle + 4 * math.pi / 3))
        draw.rectangle([frame_x, y1, frame_x + frame_thickness, y2], fill=(r, g, b, 255))
    
    # Add a bright outline around the frame
    draw.rounded_rectangle(
        [
            frame_x - 1,
            frame_y - 1,
            frame_x + frame_size + 1,
            frame_y + frame_size + 1
        ],
        radius=size * 0.08,
        outline=(255, 255, 255, 180),
        width=max(1, size // 128)
    )
    
    # Inner content area (representing the screenshot content)
    inner_padding = frame_thickness * 2
    inner_rect = [
        frame_x + inner_padding,
        frame_y + inner_padding,
        frame_x + frame_size - inner_padding,
        frame_y + frame_size - inner_padding
    ]
    
    # Draw a subtle pattern inside (representing screenshot content)
    # Use a soft gradient fill with colorful hints
    inner_height = inner_rect[3] - inner_rect[1]
    inner_width = inner_rect[2] - inner_rect[0]
    step = max(1, int(size // 32))
    
    for y in range(int(inner_rect[1]), int(inner_rect[3]), step):
        # Create a subtle gradient with colorful accents
        progress = (y - inner_rect[1]) / inner_height if inner_height > 0 else 0
        base_r = int(220 + progress * 20)
        base_g = int(230 + progress * 15)
        base_b = int(250 - progress * 30)
        
        # Add subtle color variations
        variation = int(math.sin(progress * math.pi * 4) * 15)
        r = max(200, min(255, base_r + variation))
        g = max(210, min(255, base_g + variation))
        b = max(220, min(255, base_b + variation))
        
        y_end = min(int(inner_rect[3]), y + step)
        if y_end > y:
            draw.rectangle(
                [int(inner_rect[0]), y, int(inner_rect[2]), y_end],
                fill=(int(r), int(g), int(b), 200)
            )
    
    # Add some decorative elements to represent screenshot content
    # Small colorful dots/patterns
    num_dots = max(3, size // 64)
    for i in range(num_dots):
        dot_x = inner_rect[0] + (i + 1) * inner_width / (num_dots + 1)
        dot_y = inner_rect[1] + inner_height * 0.3 + (i % 2) * inner_height * 0.4
        dot_size = max(1, size // 64)
        
        # Colorful dots
        colors = [
            (255, 120, 120, 180),
            (120, 200, 255, 180),
            (120, 255, 180, 180),
            (255, 220, 120, 180),
        ]
        draw.ellipse(
            [
                dot_x - dot_size,
                dot_y - dot_size,
                dot_x + dot_size,
                dot_y + dot_size
            ],
            fill=colors[i % len(colors)]
        )
    
    # Add a small camera/shutter icon at the top-right
    shutter_size = size * 0.15
    shutter_x = frame_x + frame_size - shutter_size * 0.3
    shutter_y = frame_y - shutter_size * 0.2
    
    # Draw circular shutter button
    shutter_center = (shutter_x, shutter_y)
    shutter_radius = shutter_size / 2
    
    # Outer ring
    draw.ellipse(
        [
            shutter_center[0] - shutter_radius,
            shutter_center[1] - shutter_radius,
            shutter_center[0] + shutter_radius,
            shutter_center[1] + shutter_radius
        ],
        fill=(255, 100, 100, 255),  # Vibrant red
        outline=(255, 255, 255, 200),
        width=max(1, size // 64)
    )
    
    # Inner circle
    inner_radius = shutter_radius * 0.6
    draw.ellipse(
        [
            shutter_center[0] - inner_radius,
            shutter_center[1] - inner_radius,
            shutter_center[0] + inner_radius,
            shutter_center[1] + inner_radius
        ],
        fill=(255, 255, 255, 255)
    )
    
    # Add a small highlight on the shutter
    highlight_radius = inner_radius * 0.3
    draw.ellipse(
        [
            shutter_center[0] - highlight_radius,
            shutter_center[1] - highlight_radius - inner_radius * 0.2,
            shutter_center[0] + highlight_radius,
            shutter_center[1] + highlight_radius - inner_radius * 0.2
        ],
        fill=(255, 255, 255, 150)
    )
    
    # Apply a subtle blur for the translucent macOS effect
    if size >= 256:
        img = img.filter(ImageFilter.GaussianBlur(radius=0.5))
    
    return img

def create_iconset():
    """Create all icon sizes and package into .iconset"""
    iconset_dir = "ScreenshotManager.iconset"
    
    # Remove existing iconset if it exists
    if os.path.exists(iconset_dir):
        import shutil
        shutil.rmtree(iconset_dir)
    
    os.makedirs(iconset_dir)
    
    # Required icon sizes for macOS
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
    
    print("Generating icon sizes...")
    for size, filename in sizes:
        print(f"  Creating {filename} ({size}x{size})...")
        icon = create_icon(size)
        icon.save(os.path.join(iconset_dir, filename), "PNG")
    
    print(f"\n✅ Icon set created: {iconset_dir}/")
    print("\nTo convert to .icns format, run:")
    print(f"  iconutil -c icns {iconset_dir}")
    
    return iconset_dir

if __name__ == "__main__":
    create_iconset()
