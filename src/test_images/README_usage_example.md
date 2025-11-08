----------------------------------------------------------------------------------
-- Example: Modified CNN Testbench Using Real Quick Draw Data
-- 
-- This shows the minimal changes needed to test with real data instead of
-- synthetic test patterns. 
--
-- To use this:
-- 1. Run: python model/export_test_image.py --category apple --index 0
-- 2. Replace the test image generation in cnn_tb.vhd with this approach
----------------------------------------------------------------------------------

-- Add this to your library/use section:
use work.test_image_pkg.all;  -- Provides TEST_IMAGE_DATA, TEST_IMAGE_LABEL, TEST_IMAGE_CATEGORY

-- Replace your generate_test_image function with this:

function generate_test_image return test_image_type is
    variable temp_image : test_image_type;
begin
    -- Load real Quick Draw data from exported package
    for row in 0 to IMAGE_SIZE-1 loop
        for col in 0 to IMAGE_SIZE-1 loop
            temp_image(row, col) := TEST_IMAGE_DATA(row, col);
        end loop;
    end loop;
    return temp_image;
end function;

-- Optional: Add reporting at simulation start to show what image is being tested
-- (add this in your main test process, after reset):

report "Testing with real Quick Draw image: " & TEST_IMAGE_CATEGORY 
       & " (expected label: " & integer'image(TEST_IMAGE_LABEL) & ")"
       severity note;

-- That's it! The rest of your testbench remains unchanged.
-- The test_image signal will now contain real drawing data instead of (row+col+1) pattern.

----------------------------------------------------------------------------------
-- Complete Working Example (minimal changes to cnn_tb.vhd)
----------------------------------------------------------------------------------
-- 
-- 1. Add to library section (around line 28):
--    use work.test_image_pkg.all;
--
-- 2. Replace function at line ~101 with:
--    function generate_test_image return test_image_type is
--        variable temp_image : test_image_type;
--    begin
--        for row in 0 to IMAGE_SIZE-1 loop
--            for col in 0 to IMAGE_SIZE-1 loop
--                temp_image(row, col) := TEST_IMAGE_DATA(row, col);
--            end loop;
--        end loop;
--        return temp_image;
--    end function;
--
-- 3. Add after reset sequence (around line 180):
--    report "Testing with: " & TEST_IMAGE_CATEGORY & 
--           " (label " & integer'image(TEST_IMAGE_LABEL) & ")" severity note;
--
-- That's all! Your simulation will now use real Quick Draw data.
----------------------------------------------------------------------------------
