"""Exact article-number inventory and bounded header batches."""
import nntplib


def article_numbers(client,group):
    # Python 3.9 nntplib does not expose LISTGROUP as a public method.
    _,lines=client._longcmdstring('LISTGROUP '+group)
    return sorted({int(line) for line in lines if line.isdigit() and int(line)>0})


def number_ranges(numbers):
    ranges=[]
    for number in sorted(set(numbers)):
        if ranges and number==ranges[-1][1]+1:
            ranges[-1][1]=number
        else:
            ranges.append([number,number])
    return ranges


def selected_headers(client,numbers):
    if not isinstance(numbers,list) or len(numbers)>500 or any(type(n) is not int or n<=0 for n in numbers):
        raise ValueError('每批最多 500 個有效文章編號')
    rows=[]
    for start,end in number_ranges(numbers):
        try:
            rows.extend(client.over((start,end))[1])
        except nntplib.NNTPTemporaryError as error:
            if not str(error).startswith(('420','423')):
                raise
    return rows
