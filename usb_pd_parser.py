import fitz # PyMuPDF
import json
import re
import os

# README:
# This script parses the Table of Contents (ToC) from a USB Power Delivery (USB PD) specification PDF.
#
# How it works:
# 1. Configuration: Key parameters like file paths and the page range for the ToC are defined.
# 2. Text Extraction: It uses the PyMuPDF library to extract raw text from the specified ToC pages.
# 3. Regex Parsing: It iterates through each line of the extracted text and applies a regular expression
#    to identify and capture the section ID, title, and page number.
# 4. Data Structuring & Inference: For each match, it:
#    - Extracts section_id, title, and page.
#    - Infers the hierarchy 'level' from the number of dots in the section_id.
#    - Infers the 'parent_id' by truncating the section_id string.
#    - Creates a dictionary for the ToC entry, matching the required JSON structure.
# 5. JSONL Output: The script writes the list of dictionaries to a '.jsonl' file, with each
#    entry as a new line.
#
# Bonus Points:
# - Reusable Functions: The logic is separated into functions for extraction, parsing, and writing.
# - Robust Error Handling: Includes try-except blocks for file operations to handle potential errors.


def extract_toc_text(pdf_path: str, page_range: tuple) -> str:
    """
    Extracts raw text from a specified range of pages in a PDF file.

    Args:
        pdf_path: The path to the PDF file.
        page_range: A tuple (start_page, end_page) of 1-based page numbers.

    Returns:
        A single string containing all the text from the specified pages.
    """
    full_text = ""
    try:
        doc = fitz.open(pdf_path)
        # Convert 1-based page range to 0-based index for PyMuPDF
        start_page, end_page = page_range[0] - 1, page_range[1] - 1
        
        for page_num in range(start_page, end_page + 1):
            if page_num < len(doc):
                page = doc.load_page(page_num)
                full_text += page.get_text("text")
        doc.close()
    except FileNotFoundError:
        print(f"Error: The file '{pdf_path}' was not found.")
        return ""
    except Exception as e:
        print(f"An error occurred while processing the PDF: {e}")
        return ""
    return full_text


def parse_toc_data(toc_text: str, doc_title: str) -> list[dict]:
    """
    Parses the raw ToC text into a list of structured dictionaries.

    Args:
        toc_text: A string containing the text of the Table of Contents.
        doc_title: The title of the document.

    Returns:
        A list of dictionaries, where each dictionary represents a section.
    """
    parsed_entries = []
    
    # Corrected Regex:
    # This pattern is more flexible. It captures:
    # 1. section_id: Starts with a digit, followed by optional non-capturing groups of a dot and more digits.
    # 2. title: The rest of the line, non-greedily, until it hits the final whitespace/dots and page number.
    # 3. page: The page number at the very end of the line.
    toc_line_regex = re.compile(r"^(?P<id>\d+(?:\.\d+)*)\s+(?P<title>.*?)\s*\.*\s*(?P<page>\d+)$")

    for line in toc_text.splitlines():
        line = line.strip()
        match = toc_line_regex.match(line)
        
        if match:
            section_id = match.group("id")
            title = match.group("title").strip()
            page = int(match.group("page"))
            
            level = section_id.count('.') + 1
            
            if '.' in section_id:
                parent_id = section_id.rpartition('.')[0]
            else:
                parent_id = None
            
            full_path = f"{section_id} {title}"

            entry = {
                "doc_title": doc_title,
                "section_id": section_id,
                "title": title,
                "page": page,
                "level": level,
                "parent_id": parent_id,
                "full_path": full_path
            }
            parsed_entries.append(entry)
            
    return parsed_entries


def write_to_jsonl(data: list[dict], output_path: str):
    """
    Writes a list of dictionaries to a JSONL file.

    Args:
        data: A list of dictionaries to write.
        output_path: The path for the output .jsonl file.
    """
    try:
        with open(output_path, 'w', encoding='utf-8') as f:
            for item in data:
                f.write(json.dumps(item) + '\n')
        print(f"Successfully created JSONL file at: {output_path}")
    except IOError as e:
        print(f"Error writing to file '{output_path}': {e}")


def main():
    """Main function to orchestrate the parsing and file generation."""
    # --- Configuration ---
    PDF_PATH = "/home/soma/Documents/soma_docs/Vinay/grl/USB_PD_R3_2 V1.1 2024-10.pdf"
    OUTPUT_PATH = "usb_pd_spec.jsonl"
    
    # Define the page range for the Table of Contents (1-based).
    TOC_PAGE_RANGE = (1, 10)
    
    DOC_TITLE = "USB Power Delivery Specification Rev X"

    # --- Execution ---
    if not os.path.exists(PDF_PATH):
        print(f"Error: Input file not found at '{PDF_PATH}'.")
        print("Please make sure the file path, name, and extension are correct.")
        return

    toc_text = extract_toc_text(PDF_PATH, TOC_PAGE_RANGE)
    
    if toc_text:
        parsed_data = parse_toc_data(toc_text, DOC_TITLE)
        
        if parsed_data:
            write_to_jsonl(parsed_data, OUTPUT_PATH)
        else:
            print("Could not parse any entries from the Table of Contents.")
            print("Please check the TOC_PAGE_RANGE and the PDF file's text format.")

if __name__ == "__main__":
    main()
