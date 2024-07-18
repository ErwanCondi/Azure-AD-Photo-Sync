using namespace System.Collections
using namespace System.Drawing
using namespace System.Drawing.Drawing2D
using namespace System.Drawing.Imaging
using namespace System.Drawing.Text
using namespace System.IO

enum ActionName{
    Add
    Update
    Remove
}

enum MessageType{
    Info
    Error
    Warning
}

enum ActionResults{
    NotStarted
    Success
    Skipped
    Error
}

class Print{
    static [void]Display(
        [string]$message,
        [MessageType]$messageType = [MessageType]::Info
    ){
        [string]$category = [string]
        [string]$ForegroundColor = [string]

        switch ($messageType.value__){
            0 {
                $category = $messageType.ToString() + "   "
                $ForegroundColor = "White"
                }
            1 {
                $category = $messageType.ToString() + "  "
                $ForegroundColor = "Red"
                }
            2 {
                $category = $messageType.ToString()
                $ForegroundColor = "Yellow"
                }
        }

        Write-Host "$([datetime]::Now)   $($category)   $message" -ForegroundColor $ForegroundColor -BackgroundColor Black
    }
}

class Action{
    [DateTime]$Created
    [String]$ActionId
    [ActionName]$ActionName
    [String]$ThirdParty
    [Boolean]$IsActive
    [ActionResults]$ActionResults
    [PSCustomObject]$User
    [Int32]$Attempts
    [ArrayList]$Error
    [String]$CurrentPicture
    [String]$NewPicture

    Action([String]$ActionName, [String]$ThirdParty, [PSCustomObject]$User){
        $this.Created = [DateTime]::Now
        $this.ActionId = [guid]::NewGuid().Guid.Replace('-', '').Substring(0, 15)
        $this.ActionName = $ActionName
        $this.ThirdParty = $ThirdParty
        $this.IsActive = $true
        $this.ActionResults = 'NotStarted'
        $this.User = $User
        $this.Attempts = 0
        $this.Error = [ArrayList]::new()
    }
    Action([PSObject]$SavedAction){
        $this.Created       = $SavedAction.Created
        $this.ActionId      = $SavedAction.ActionId
        $this.ActionName    = $SavedAction.ActionName
        $this.ThirdParty    = $SavedAction.ThirdParty
        $this.IsActive      = $SavedAction.IsActive
        $this.ActionResults = $SavedAction.ActionResults
        $this.User          = $SavedAction.User
        $this.Attempts      = $SavedAction.Attempts
        $this.Error         = $SavedAction.Error

        if($SavedAction.CurrentPicture){
            $this.CurrentPicture = $SavedAction.CurrentPicture
        }
        if($SavedAction.NewPicture){
            $this.NewPicture     = $SavedAction.NewPicture
        }
    }
}

class UserImage{
    [byte[]]$PictureByte
    [string]$PicturePath

    # constructor providing byte array directly
    hidden UserImage([byte[]]$PictureByte){
        $this.PictureByte = $PictureByte
    }
    # constructor to store the bytearray and filepath
    hidden UserImage([byte[]]$PictureByte, $FilePath){
        $this.PictureByte = $PictureByte
        $this.PicturePath = $FilePath
    }
    # constructor to create a picture from a string
    hidden UserImage([String]$Text){
        # Select a random background color from the list
        $colors = $("Aqua","Aquamarine","Bisque","Black","Blue","BlueViolet","Brown","BurlyWood","ButtonShadow","CadetBlue","Chartreuse","Chocolate","Coral","CornflowerBlue","Crimson","Cyan","DarkBlue","DarkCyan","DarkGoldenrod","DarkGray","DarkGreen","DarkKhaki","DarkMagenta","DarkOliveGreen","DarkOrange","DarkOrchid","DarkRed","DarkSalmon","DarkSeaGreen","DarkSlateBlue","DarkSlateGray","DarkTurquoise","DarkViolet","DeepPink","DeepSkyBlue","Desktop","DimGray","DodgerBlue","Firebrick","ForestGreen","Fuchsia","Gainsboro","Gold","Goldenrod","GradientActiveCaption","GradientInactiveCaption","Gray","Green","GreenYellow","HotPink","IndianRed","Indigo","Khaki","Lavender","LawnGreen","LightBlue","LightCoral","LightGray","LightGreen","LightPink","LightSalmon","LightSeaGreen","LightSkyBlue","LightSlateGray","LightSteelBlue","Lime","LimeGreen","Magenta","Maroon","MediumAquamarine","MediumBlue","MediumOrchid","MediumPurple","MediumSeaGreen","MediumSlateBlue","MediumSpringGreen","MediumTurquoise","MediumVioletRed","MidnightBlue","MistyRose","Moccasin","NavajoWhite","Navy","Olive","OliveDrab","Orange","OrangeRed","Orchid","PaleGreen","PaleTurquoise","PaleVioletRed","PeachPuff","Peru","Pink","Plum","PowderBlue","Purple","Red","RosyBrown","RoyalBlue","SaddleBrown","Salmon","SandyBrown","SeaGreen","Sienna","Silver","SkyBlue","SlateBlue","SlateGray","SpringGreen","SteelBlue","Tan","Teal","Thistle","Tomato","Turquoise","Violet","Wheat","YellowGreen")
        $backgroundColor = [color]::FromName( $($colors | Get-Random ))
        
        # create the Font
        $font = [Font]::New("Microsoft Sans Serif", 200, [FontStyle]::Bold)

        # first, create a dummy bitmap just to get a graphics object
        [Image] $img = [Bitmap]::new(1,1)
        [Graphics] $drawing = [Graphics]::FromImage($img)

        # measure the string to see how big the image needs to be
        [SizeF] $textSize = $drawing.MeasureString($text, $font)

        # set the stringformat flags to rtl
        [StringFormat] $sf = [StringFormat]::new()
        $sf.Trimming = [StringTrimming]::Word

        # free up the dummy image and old graphics object
        $img.Dispose()
        $drawing.Dispose()

        # create a new image of the right size
        $img = [Bitmap]::new([int]$($textSize.Width * 1.5), [int]$($textSize.Height * 1.5))

        $drawing = [Graphics]::FromImage($img)

        # Adjust for high quality
        $drawing.CompositingQuality = [CompositingQuality]::HighQuality
        $drawing.InterpolationMode = [InterpolationMode]::HighQualityBilinear
        $drawing.PixelOffsetMode = [PixelOffsetMode]::HighQuality
        $drawing.SmoothingMode = [SmoothingMode]::HighQuality
        $drawing.TextRenderingHint = [TextRenderingHint]::AntiAliasGridFit
    
        # paint the background
        $drawing.Clear($backgroundColor)

        # create a brush for the text
        [Brush] $textBrush = [SolidBrush]::new([Color]::White)

        $posX = ($img.Width  - $textSize.Width)  / 2
        $posY = ($img.Height - $textSize.Height) / 2 * 1.25
        $rectangle = [RectangleF]::new($posX, $posY, $textSize.Width, $textSize.Height)

        $drawing.DrawString($text, $font, $textBrush, $rectangle, $sf)
        $drawing.Save()
        
        [ImageConverter] $converter = [ImageConverter]::new()
        
        $this.PictureByte = [byte[]]$converter.ConvertTo($img, [byte[]])
    }
    
    # constructor to create a picture from user's initials - First Name + Last name
    static [UserImage]CreateFromInitials([String]$stringA, [String]$stringB){
        $txt = $stringA[0] + $stringB[0]
        return [UserImage]::New($txt)
    }
    # constructor to create a picture from user's initials - Only firstname
    static [UserImage]CreateFromInitials([String]$stringA){
        if ($stringA.Length -ge 2){
            $txt = $stringA[0] + $stringA[1]
        }
        else{
            $txt = $stringA[0] + '.'
        }
        return [UserImage]::New($txt)
    }

    # constructor reading from file
    static [UserImage]GetFromFile([String]$FilePath){
        [byte[]]$byte = [File]::ReadAllBytes($FilePath)
        return [UserImage]::New($byte, $FilePath)
    }

    # constructor reading from byte array
    static [UserImage]GetFromByteArray([byte[]]$PictureByte){
        return [UserImage]::New($PictureByte)
    }

    # To create another object based on the same byte array
    [UserImage]Clone(){
        return [UserImage]::New($this.PictureByte)
    }

    # To resize a picture to desired size and weight
    [void]Resize([int]$targetSize, [int]$maxWeight){
        # Convert the byte array to an System.Drawing.Image object
        $image = [Image]::FromStream([MemoryStream]::new($this.PictureByte))

        # decide if the picture actually needs to be resized or not
        if ($image.Width -gt $targetSize -or $image.Height -gt $targetSize){
            # Calculate the image ratio, height and width
            if ($image.Width -gt $image.Height){
                $ratio = $image.Width / $image.Height
                $height = [Convert]::ToInt32($targetSize / $ratio)
                $width = $targetSize
            }
            else{
                $ratio = $image.Height / $image.Width;
                $height = $targetSize
                $width = [Convert]::ToInt32($height / $ratio);
            }

            # Create the surface for the image
            $destRect = [Rectangle]::new(0, 0, $width, $height)

            # Create a recipient image
            $destImage = [Bitmap]::new($width, $height)
            $destImage.SetResolution($image.HorizontalResolution, $image.VerticalResolution)

            # Add all image settings
            $graphics = [Graphics]::FromImage($destImage)
            $graphics.CompositingMode = [CompositingMode]::SourceCopy
            $graphics.CompositingQuality = [CompositingQuality]::HighQuality
            $graphics.InterpolationMode = [InterpolationMode]::HighQualityBicubic
            $graphics.SmoothingMode = [SmoothingMode]::HighQuality
            $graphics.PixelOffsetMode = [PixelOffsetMode]::HighQuality

            # Set wrap mode (how the texture is drawn on the surface)
            $wrapMode = [ImageAttributes]::new()
            $wrapMode.SetWrapMode([WrapMode]::TileFlipXY)

            # Draw the image onto the the surface
            $graphics.DrawImage($image, $destRect, 0, 0, $image.Width,$image.Height, [GraphicsUnit]::Pixel, $wrapMode)

            # Get the correct jpeg encoder
            $jpegEncoder = [ImageCodecInfo]::GetImageEncoders() | ? { $_.MimeType -eq 'image/jpeg' }
            
            # Quality starts at 100 and is decreased every loop until the picture size is lower than the requested MaxWeight
            $quality = 100
            $retries = 0
            do{
                $retries ++
                $encoderParameters = [EncoderParameters]::new(1)
                $encoderParameters.Param = [EncoderParameter]::new([Encoder]::Quality, $quality)

                $ms = [MemoryStream]::new()
                $destImage.Save($ms, $jpegEncoder, $encoderParameters)
                $quality--
                [console]::WriteLine( $ms.Length.ToString() )
            } while ($ms.Length -gt $maxWeight -and $retries -gt 10)
            
            # Create the output [byte[]]
            $this.PictureByte = $ms.ToArray()
        }
    }

    # to write an image to a file
    [void]WriteImageToFile([string]$FilePath){
        $this.PicturePath = $FilePath
        $memStream = [MemoryStream]::new($this.PictureByte)
        $image = [Image]::FromStream($memStream)
        $image.Save($this.PicturePath)
    }
}